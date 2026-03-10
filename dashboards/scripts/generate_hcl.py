import os
import json
import http.client
import sys
import argparse

# --- Constants ---
ANTHROPIC_HOST = "api.anthropic.com"
ANTHROPIC_PATH = "/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"

def load_env():
    """Load ANTHROPIC_API_KEY from .env file synchronously."""
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if not os.path.exists(env_path):
        print(f"Error: .env file not found at {env_path}")
        sys.exit(1)
    
    with open(env_path, "r") as f:
        for line in f:
            if line.startswith("ANTHROPIC_API_KEY="):
                return line.strip().split("=")[1]
    
    print("Error: ANTHROPIC_API_KEY not found in .env")
    sys.exit(1)

def call_anthropic_api(api_key, system_prompt, user_prompt, model="claude-3-haiku-20240307"):
    """Call the Claude API using standard http.client."""
    conn = http.client.HTTPSConnection(ANTHROPIC_HOST)
    
    payload = json.dumps({
        "model": model,
        "max_tokens": 4096,
        "system": system_prompt,
        "messages": [
            {"role": "user", "content": user_prompt}
        ]
    })
    
    headers = {
        "x-api-key": api_key,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json"
    }
    
    try:
        conn.request("POST", ANTHROPIC_PATH, payload, headers)
        res = conn.getresponse()
        data = res.read()
        
        if res.status != 200:
            error_text = data.decode('utf-8')
            print("\n" + "!"*60)
            print(f"ANTHROPIC API ERROR ({res.status})")
            if "overloaded" in error_text.lower():
                print("The model is currently overloaded. Please wait a minute and try again.")
            elif "rate_limit" in error_text.lower() or "credit_balance" in error_text.lower():
                print("You may have hit a Rate Limit or have insufficient credits.")
                print("Please check your Anthropic dashboard.")
            else:
                print(f"Error details: {error_text}")
            print("!"*60 + "\n")
            sys.exit(1)
            
        response_json = json.loads(data.decode('utf-8'))
        return response_json['content'][0]['text']
    except Exception as e:
        print(f"\nConnection Error: {e}")
        print("Please check your internet connection and ANTHROPIC_API_KEY.\n")
        sys.exit(1)
    finally:
        conn.close()

def main():
    parser = argparse.ArgumentParser(description="Generate Metabase Terraform code using AI from a JSON file")
    parser.add_argument("input_json", help="Path to the exported Metabase JSON file (e.g., generated/dashboard_6.json)")
    parser.add_argument("--output", "-o", help="Output file name (default: generated/dashboard_<name>_hcl.tf.ref)")
    args = parser.parse_args()

    if not os.path.exists(args.input_json):
        print(f"Error: Could not find input file at {args.input_json}")
        sys.exit(1)

    with open(args.input_json, "r") as f:
        json_content = f.read()

    api_key = load_env()
    
    # Load reference from metabase.tf for context
    tf_path = os.path.join(os.path.dirname(__file__), "..", "metabase.tf")
    reference_code = ""
    if os.path.exists(tf_path):
        with open(tf_path, "r") as f:
            reference_code = f.read()

    system_prompt = f"""You are a Terraform expert specialized in the 'flovouin/metabase' provider.
Your task is to convert Metabase dashboard JSON into Terraform HCL.

CRITICAL RULES:
1. Portability Rule: Do NOT use MBQL/GUI queries with field IDs. Convert all cards to Native SQL queries using column names (e.g., SELECT ... FROM analytics.table).
2. Tab Mapping Rule: Map dashboard cards to the correct `dashboard_tab_id` using the ID defined in the `tabs_json` block of the existing `metabase_dashboard.tenant_analytics` resource.
3. Pattern Rule: Use `for_each = var.tenants` and reference resources using `[each.key]`.
4. HCL Structure: The 'flovouin/metabase' provider requires `json = jsonencode({{ ... }})` for `metabase_card`.
5. Consistency Rule: To avoid "inconsistent result" errors, you MUST include ALL boilerplate fields in the JSON (description, cache_ttl, parameters, etc.) even if they are null.
6. Dashboard Cards: The `cards_json` attribute in `metabase_dashboard` MUST be a list of objects containing `card_id = tonumber(metabase_card.NAME[each.key].id)`. You MUST also include `parameter_mappings = []`, `series = []`, and `visualization_settings = {{}}` for each card entry.
7. Multi-Tenant Branding: Dashboard and Card names MUST use dynamic interpolation. For example, use `name = "${{each.value.display_name}} Dashboard"` instead of hardcoded names like "North Carolina Dashboard".

NEGATIVE CONSTRAINTS (DO NOT DO THESE):
1. NO API DUMPING: Do NOT copy raw fields from the Metabase API response (like `lib_breakout?`, `entity_id`, `enable_embedding`, `parameters`, `auto_apply_filters`, `can_write`, `archived`, etc.) into the HCL. These are either invalid HCL identifiers or unsupported by the Terraform provider.
2. NO EMBEDDED CARDS: Do NOT include a `card = {{ ... }}` block inside `cards_json`. Only provide the `card_id`, `row`, `col`, `size_x`, `size_y`, and `dashboard_tab_id`.
3. NO RAW IDS: Never use raw integer IDs for cards (e.g., `card_id = 93`) or fields (e.g., `["field", 1421, ...]`).
    *   **Cards**: Always use `tonumber(metabase_card.NAME[each.key].id)`.
    *   **Fields**: Always use `tonumber(data.metabase_table.TABLE_NAME[each.key].fields["COLUMN_NAME"])`.
4. NO METADATA OR POSITIONS: In `tabs_json`, DO NOT include `entity_id`, `position`, or other unneeded Metabase metadata. ONLY include `id` and `name`.

EXAMPLE HCL PATTERN:
```hcl
resource "metabase_card" "tenant_metric" {{
  for_each = var.tenants
  json = jsonencode({{
    name                = "Metric Name"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "query"
    dataset_query = {{
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "query"
      query = {{
        source-table = tonumber(data.metabase_table.tenant_screen_summary_tables[each.key].id)
        aggregation  = [["count"]]
      }}
    }}
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {{}}
    parameters             = []
  }})
}}

resource "metabase_dashboard" "tenant_analytics" {{
  for_each = var.tenants
  ...
  cards_json = jsonencode([
    {{
      card_id          = tonumber(metabase_card.tenant_metric[each.key].id)
      dashboard_tab_id = 460
      row              = 0
      col              = 0
      size_x           = 6
      size_y           = 4
      parameter_mappings = []
      series           = []
      visualization_settings = {{}}
    }}
  ])
}}
```

EXISTING CODE FOR CONTEXT:
{reference_code[:4000]} 
"""

    user_prompt = f"""Convert this Metabase dashboard JSON into a TEMPLATIZED Terraform resource named "tenant_analytics" that uses for_each = var.tenants.
Ensure it looks exactly like the existing "tenant_analytics" dashboard but updated with the new tabs/cards from this JSON.

JSON DATA:
{json_content}
"""
    print(f"Generating Terraform HCL...")
    generated_code = call_anthropic_api(api_key, system_prompt, user_prompt)
    
    # Extraction logic
    if "```hcl" in generated_code:
        generated_code = generated_code.split("```hcl")[1].split("```")[0].strip()
    elif "```" in generated_code:
        generated_code = generated_code.split("```")[1].split("```")[0].strip()

    # Determine output path
    output_file = args.output
    if not output_file:
        base_name = os.path.basename(args.input_json).replace(".json", "")
        output_dir = os.path.dirname(args.input_json)
        output_file = os.path.join(output_dir, f"{base_name}_hcl.tf.ref")
        
    print(f"Writing generated HCL to {output_file}...")
    with open(output_file, "w") as f:
        f.write(generated_code)
        
    print(f"\nSuccess! Code saved to {output_file}")
    print(f"You can now review the file and manually copy the blocks you want into metabase.tf.")

if __name__ == "__main__":
    main()
