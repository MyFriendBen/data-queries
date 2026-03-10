## Metabase Dashboard Generation Helper

This workflow is intended as **reference tool**. While it handles common patterns, specific edge cases or complex visualizations may not be perfectly translated and may require manual adjustments.

This workflow assumes you have already:
1.  **Modified a Dashboard in the Metabase UI** (e.g., added tabs, moved cards, created new questions).
2.  **Identified the Dashboard ID**: Grab the number from the end of the URL when viewing that dashboard in your browser (e.g., `.../dashboard/6-north-carolina` -> ID is **6**).

## The 2-Step Workflow

The scripts output temporary reference files. You review these files and manually copy the blocks you need.

### Script 1: Export Dashboard JSON
**Script:** `export_dashboard_json.py`

This script connects to the Metabase API using credentials from `terraform.tfvars` and downloads the raw JSON definition of a dashboard. **You do NOT need an Anthropic API key to run this**.

**Usage:**
```bash
python3 scripts/export_dashboard_json.py <dashboard-id>
```
*Example:* `python3 scripts/export_dashboard_json.py 6`

**Output:**
This will save the JSON to `scripts/generated/dashboard_6.json`.

---

### Script 2: Generate Terraform HCL
**Script:** `generate_hcl.py`

This script reads a local JSON file generated in Step 1 and uses the Anthropic API (Claude 3) to convert it into Terraform HCL. It requires an `ANTHROPIC_API_KEY` in your `.env` file under `/dashboards`.

**Usage:**
```bash
python3 scripts/generate_hcl.py <path-to-json-file>
```
*Example:* `python3 scripts/generate_hcl.py scripts/generated/dashboard_6.json`

**Output:**
This will output a file named `scripts/generated/dashboard_6_hcl.tf.ref`.

The `.tf.ref` extension is intentional! It tricks Terraform into ignoring the file. If we used a standard `.tf` extension, running `terraform init` or `plan` might throw a "Duplicate Resource" error because Terraform loads all `.tf` files in the directory.

---

### Step 3: Review and Copy 
Open the generated `.tf.ref` file in your editor. Review the code to ensure it follows multi-tenant patterns.

**Where to put the code:**
1.  **New Cards**: If the script generated new `metabase_card` resources, copy and paste them into your Terraform configuration.
2.  **Updated Dashboard**: Use the generated `metabase_dashboard` resource to update your existing dashboard configuration. Ensure the `tabs_json` and `cards_json` line up with the new cards you just added.

## Why We Use Example Patterns in the Prompt
Inside `generate_hcl.py`, you will see a detailed prompt containing an example HCL pattern. These specific details helped fix several critical errors encountered during development, though they serve primarily as a starting point:

1.  **Metabase Provider Quirks**: The `flovouin/metabase` provider requires wrapping card settings in a `jsonencode()` block.
2.  **Inconsistent Results Error**: Upon creating a card or dashboard, Metabase automatically populates fields (like `cache_ttl`, `description`). We include these boilerplate fields as defaults in both the **card resources** and the **`cards_json` entries** to satisfy the provider and prevent drift errors.
3.  **Required vs. Metadata IDs**: 
    *   KEEP: Numeric `id` (in `tabs_json`) and `dashboard_tab_id` (in `cards_json`). These are REQUIRED to link cards to the correct tabs.
    *   REMOVE: Strings like `entity_id` (e.g., `axV0Xby...`) or other Metabase-internal tracking fields. These are unnecessary metadata.


This script is a reference assistant, not a fully automated solution. It may not handle all specific dashboard configurations or complex visualization settings.

## Technical Details (API Calls)

### 1. Metabase Authentication
- **Endpoint**: `POST /api/session`
- **Payload**: `{ "username": "...", "password": "..." }`
- **Response**: Returns a session `id` used in subsequent headers as `X-Metabase-Session`.

### 2. Dashboard Export
- **Endpoint**: `GET /api/dashboard/<dashboard-id>`
- **Header**: `X-Metabase-Session: <sid>`
- **Response**: Full JSON object of the dashboard, including its tabs and card references. Used as the local input for HCL generation.

### 3. AI Generation (Anthropic)
- **Endpoint**: `POST https://api.anthropic.com/v1/messages`
- **Model**: Hardcoded as `claude-3-haiku-20240307` for consistent, fast results.
- **Payload**: Combines the system prompt, the existing `metabase.tf` for context, and the raw dashboard JSON.
- **Output**: Cleaned HCL code wrapped in `.tf.ref` for safe manual review.

### Git ignore
The `scripts/generated/` folder is ignored in `.gitignore`. Do not commit raw API JSON dumps or temporary `.tf.ref` files.
