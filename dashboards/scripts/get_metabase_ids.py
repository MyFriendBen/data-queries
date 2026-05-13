#!/usr/bin/env python3
"""Fetch all database IDs and permission group IDs from Metabase.

Workaround for a bug in flovouin/terraform-provider-metabase where the
metabase_permissions_graph data source crashes when create-queries is
returned as a schema-level object rather than a flat string. This script
queries /api/database and /api/permissions/group directly — endpoints that
don't include permission data and can't trigger the crash.

See: https://github.com/flovouin/terraform-provider-metabase/issues (upstream)

Input (JSON on stdin):
  {
    "metabase_url": "http://localhost:3001",
    "username": "admin@example.com",
    "password": "secret"
  }

Output (JSON on stdout – flat string values for Terraform external data source):
  {"db_ids": "[1, 2, 3]", "group_ids": "[1, 2, 3, 4]"}
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
        raise SystemExit(
            f"{context} failed with HTTP {exc.code}: {exc.reason}"
        ) from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"{context} failed: {exc.reason}") from exc


def get_session(metabase_url, username, password):
    req = urllib.request.Request(
        f"{metabase_url}/api/session",
        data=json.dumps({"username": username, "password": password}).encode(),
        headers={"Content-Type": "application/json"},
    )
    return _load_json(req, "Creating Metabase session")["id"]


def delete_session(base_url, session_id):
    req = urllib.request.Request(
        f"{base_url}/api/session",
        headers={"X-Metabase-Session": session_id},
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SECONDS):
            pass
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass  # best-effort; don't mask the real result


_PAGE_SIZE = 50


def _get_all_databases(base_url, headers):
    db_list = []
    offset = 0

    while True:
        req = urllib.request.Request(
            f"{base_url}/api/database?limit={_PAGE_SIZE}&offset={offset}",
            headers=headers,
        )

        data = _load_json(req, "Listing Metabase databases")

        if isinstance(data, dict):
            if "data" not in data:
                raise SystemExit(f"Unexpected Metabase database response: {data}")

            page = data["data"]
            if not isinstance(page, list):
                raise SystemExit(f"Expected 'data' to be a list, got: {type(page)}")

            total = data.get("total")
            db_list.extend(page)

            if not page or (total is not None and len(db_list) >= total):
                break

            offset += _PAGE_SIZE

        elif isinstance(data, list):
            db_list.extend(data)
            break

        else:
            raise SystemExit(
                f"Unexpected Metabase database response type: {type(data)}"
            )

    return db_list


def _get_all_groups(base_url, headers):
    # /api/permissions/group returns at most 50 items — paginate to get all.
    group_ids = []
    offset = 0
    while True:
        req = urllib.request.Request(
            f"{base_url}/api/permissions/group?limit={_PAGE_SIZE}&offset={offset}",
            headers=headers,
        )
        page = _load_json(req, "Listing Metabase permission groups")
        if not isinstance(page, list):
            raise SystemExit(f"Unexpected permissions/group response: {page}")
        group_ids.extend(g["id"] for g in page if isinstance(g, dict))
        if len(page) < _PAGE_SIZE:
            break
        offset += _PAGE_SIZE
    return group_ids


def main():
    query = json.load(sys.stdin)
    base_url = query["metabase_url"].rstrip("/")
    session_id = get_session(base_url, query["username"], query["password"])
    try:
        headers = {"X-Metabase-Session": session_id}

        db_ids = [
            db["id"] for db in _get_all_databases(base_url, headers) if isinstance(db, dict)
        ]

        group_ids = _get_all_groups(base_url, headers)

        print(
            json.dumps(
                {
                    "db_ids": json.dumps(db_ids),
                    "group_ids": json.dumps(group_ids),
                }
            )
        )
    finally:
        delete_session(base_url, session_id)


if __name__ == "__main__":
    main()
