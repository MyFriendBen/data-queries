#!/usr/bin/env python3
"""Look up Metabase field IDs for specified columns across all tenant databases.

Used by Terraform's external data source to dynamically resolve field IDs,
which differ between environments (local dev, staging, production).

Input (JSON on stdin):
  {
    "metabase_url": "http://localhost:3001",
    "username": "admin@example.com",
    "password": "secret",
    "database_ids": "{\"co\": \"3\", \"nc\": \"2\", ...}",
    "field_names": "[\"partner\", \"county\"]"
  }

Output (JSON on stdout – flat keys for Terraform external data source):
  {"co__partner": "5689", "co__county": "5690", "nc__partner": "6329", ...}
"""
import json
import sys
import urllib.error
import urllib.request

REQUEST_TIMEOUT_SECONDS = 15


def _load_json(req, context):
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SECONDS) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"{context} failed with HTTP {exc.code}: {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"{context} failed: {exc.reason}") from exc


def get_session(metabase_url, username, password):
    req = urllib.request.Request(
        f"{metabase_url}/api/session",
        data=json.dumps({"username": username, "password": password}).encode(),
        headers={"Content-Type": "application/json"},
    )
    return _load_json(req, "Creating Metabase session")["id"]


def get_field_ids(metabase_url, session_id, db_id, table_name, schema, field_names):
    """Return a dict of {field_name: field_id_str} for the requested fields."""
    req = urllib.request.Request(
        f"{metabase_url}/api/database/{db_id}/metadata?include=tables.fields",
        headers={"X-Metabase-Session": session_id},
    )
    data = _load_json(req, f"Loading metadata for database {db_id}")

    result = {}
    for table in data.get("tables", []):
        if table.get("name") == table_name and table.get("schema") == schema:
            for field in table.get("fields", []):
                if field.get("name") in field_names:
                    result[field["name"]] = str(field["id"])
    return result


def main():
    query = json.load(sys.stdin)
    metabase_url = query["metabase_url"]
    database_ids = json.loads(query["database_ids"])
    field_names = json.loads(query.get("field_names", '["partner"]'))

    session_id = get_session(metabase_url, query["username"], query["password"])

    result = {}
    missing = []
    for tenant_key, db_id in database_ids.items():
        fields = get_field_ids(
            metabase_url, session_id, db_id,
            table_name="mart_screener_data",
            schema="analytics",
            field_names=set(field_names),
        )
        for field_name in field_names:
            if field_name in fields:
                # Flat key format: tenant__field (Terraform external data returns flat map)
                result[f"{tenant_key}__{field_name}"] = fields[field_name]
            else:
                missing.append(f"{tenant_key}.{field_name} (db {db_id})")

    if missing:
        raise SystemExit(
            "Could not resolve Metabase field IDs for analytics.mart_screener_data: "
            + ", ".join(missing)
        )

    print(json.dumps(result))


if __name__ == "__main__":
    main()
