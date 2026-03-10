import os
import json
import http.client
import sys
import argparse

def load_tfvars():
    """Parse terraform.tfvars for Metabase credentials."""
    tfvars_path = os.path.join(os.path.dirname(__file__), "..", "terraform.tfvars")
    if not os.path.exists(tfvars_path):
        print(f"Error: terraform.tfvars not found at {tfvars_path}.")
        return None
    
    creds = {}
    with open(tfvars_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                val = val.split("#")[0].strip()
                creds[key.strip()] = val.strip().strip('"').strip("'")
    return creds

def get_metabase_session(url, email, password):
    """Authenticate with Metabase and return session ID."""
    from urllib.parse import urlparse
    parsed_url = urlparse(url)
    host = parsed_url.netloc
    path_prefix = parsed_url.path.rstrip('/')
    
    conn = http.client.HTTPSConnection(host) if parsed_url.scheme == "https" else http.client.HTTPConnection(host)
    payload = json.dumps({"username": email, "password": password})
    headers = {"Content-Type": "application/json"}
    
    try:
        conn.request("POST", f"{path_prefix}/api/session", payload, headers)
        res = conn.getresponse()
        data = res.read()
        
        if res.status != 200:
            print(f"Metabase Login Error ({res.status}): {data.decode('utf-8')}")
            return None
            
        try:
            return json.loads(data.decode('utf-8'))['id']
        except json.JSONDecodeError:
            print(f"Fatal: Metabase returned non-JSON response: {data.decode('utf-8')}")
            return None
    except Exception as e:
        print(f"Metabase Connection Error: {e}")
        return None
    finally:
        conn.close()

def fetch_metabase_dashboard(url, session_id, dashboard_id):
    """Fetch dashboard JSON from Metabase."""
    from urllib.parse import urlparse
    parsed_url = urlparse(url)
    host = parsed_url.netloc
    path_prefix = parsed_url.path.rstrip('/')
    
    conn = http.client.HTTPSConnection(host) if parsed_url.scheme == "https" else http.client.HTTPConnection(host)
    headers = {"Content-Type": "application/json", "X-Metabase-Session": session_id}
    
    try:
        conn.request("GET", f"{path_prefix}/api/dashboard/{dashboard_id}", headers=headers)
        res = conn.getresponse()
        data = res.read()
        
        if res.status != 200:
            print(f"Metabase Fetch Error ({res.status}): {data.decode('utf-8')}")
            return None
            
        return data.decode('utf-8')
    except Exception as e:
        print(f"Metabase Fetch Error: {e}")
        return None
    finally:
        conn.close()

def main():
    parser = argparse.ArgumentParser(description="Export a Metabase dashboard to a JSON file")
    parser.add_argument("dashboard_id", help="ID of an existing Metabase dashboard to export")
    parser.add_argument("--output", "-o", help="Output file name (default: generated/dashboard_<id>.json)")
    args = parser.parse_args()

    creds = load_tfvars()
    if not creds:
        sys.exit(1)
        
    url = creds.get('metabase_url')
    email = creds.get('metabase_admin_email')
    password = creds.get('metabase_admin_password')
    
    if not all([url, email, password]):
        print("Error: credentials missing in terraform.tfvars")
        sys.exit(1)
        
    print(f"Connecting to Metabase...")
    session_id = get_metabase_session(url, email, password)
    if not session_id:
        sys.exit(1)
        
    print(f"Fetching dashboard {args.dashboard_id}...")
    json_content = fetch_metabase_dashboard(url, session_id, args.dashboard_id)
    if not json_content:
        sys.exit(1)

    # Setup output path
    output_dir = os.path.join(os.path.dirname(__file__), "generated")
    os.makedirs(output_dir, exist_ok=True)
    
    output_file = args.output
    if not output_file:
        output_file = os.path.join(output_dir, f"dashboard_{args.dashboard_id}.json")
    else:
        # If user provides a path, ensure we can write to it
        os.makedirs(os.path.dirname(os.path.abspath(output_file)) or '.', exist_ok=True)

    with open(output_file, "w") as f:
        # Format the JSON nicely before saving
        try:
            parsed_json = json.loads(json_content)
            json.dump(parsed_json, f, indent=2)
        except:
            f.write(json_content)

    print(f"\nSuccess! Dashboard JSON saved to {output_file}")
    print(f"You can now run generate_hcl.py to convert this into Terraform HCL.")

if __name__ == "__main__":
    main()
