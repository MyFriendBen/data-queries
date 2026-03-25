#!/usr/bin/env python3
"""Look up Metabase field IDs for the partner column across all tenant databases.

Used by Terraform's external data source to dynamically resolve field IDs,
which differ between environments (local dev, staging, production).

Input (JSON on stdin):
  {
    "metabase_url": "http://localhost:3001",
    "username": "admin@example.com",
    "password": "secret",
    "database_ids": "{\"co\": \"3\", \"nc\": \"2\", ...}"
  }

Output (JSON on stdout):
  {"co": "5689", "nc": "6329", ...}
"""
import json
import sys
import urllib.request


def get_session(metabase_url, username, password):
    req = urllib.request.Request(
        f"{metabase_url}/api/session",
        data=json.dumps({"username": username, "password": password}).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.loads(urllib.request.urlopen(req).read())["id"]


def get_field_id(metabase_url, session_id, db_id, table_name, schema, field_name):
    req = urllib.request.Request(
        f"{metabase_url}/api/database/{db_id}/metadata?include=tables.fields",
        headers={"X-Metabase-Session": session_id},
    )
    data = json.loads(urllib.request.urlopen(req).read())

    for table in data.get("tables", []):
        if table.get("name") == table_name and table.get("schema") == schema:
            for field in table.get("fields", []):
                if field.get("name") == field_name:
                    return str(field["id"])
    return ""


def main():
    query = json.load(sys.stdin)
    metabase_url = query["metabase_url"]
    database_ids = json.loads(query["database_ids"])

    session_id = get_session(metabase_url, query["username"], query["password"])

    result = {}
    for tenant_key, db_id in database_ids.items():
        field_id = get_field_id(
            metabase_url, session_id, db_id,
            table_name="mart_screener_data",
            schema="analytics",
            field_name="partner",
        )
        if field_id:
            result[tenant_key] = field_id

    print(json.dumps(result))


if __name__ == "__main__":
    main()
