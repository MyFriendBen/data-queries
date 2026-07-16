#!/usr/bin/env python3
"""Remove orphaned group rows from the Metabase data-permissions graph.

When a permission group is deleted in Metabase, its rows can linger in the
data-permissions graph. The flovouin/terraform-provider-metabase then echoes
those dead group IDs back on apply with view-data: nil, which the API rejects
with a 400 ("view-data ... received: nil"). This happened after the reverted
Washington tenant work left groups 133/134 orphaned.

This script:
  1. Lists the currently existing groups (/api/permissions/group).
  2. Fetches the data-permissions graph (/api/permissions/graph).
  3. Removes any group entry in the graph whose ID no longer exists.
  4. PUTs the cleaned graph back (using the graph's own revision number).

Run against PRODUCTION Metabase (NOT localhost):

  METABASE_URL='https://<prod-metabase>' \\
  METABASE_ADMIN_EMAIL='caton@myfriendben.org' \\
  METABASE_ADMIN_PASSWORD='<prod-password>' \\
  python3 cleanup_orphaned_permission_groups.py            # dry run, shows what it would remove
  python3 cleanup_orphaned_permission_groups.py --apply    # actually writes the cleaned graph
"""

import json
import os
import sys
import urllib.error
import urllib.request

TIMEOUT = 30


def _request(method, url, session=None, body=None):
    headers = {"Content-Type": "application/json"}
    if session:
        headers["X-Metabase-Session"] = session
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise SystemExit(f"{method} {url} -> HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"{method} {url} failed: {exc.reason}") from exc


def main():
    apply = "--apply" in sys.argv
    base = os.environ["METABASE_URL"].rstrip("/")
    email = os.environ["METABASE_ADMIN_EMAIL"]
    password = os.environ["METABASE_ADMIN_PASSWORD"]

    if "localhost" in base or "127.0.0.1" in base:
        raise SystemExit(
            f"Refusing to run against {base!r} — point METABASE_URL at PROD."
        )

    session = _request(
        "POST", f"{base}/api/session", body={"username": email, "password": password}
    )["id"]

    # Existing group IDs (paginated; 50 per page).
    existing = set()
    offset = 0
    while True:
        page = _request(
            "GET", f"{base}/api/permissions/group?limit=50&offset={offset}", session
        )
        existing.update(g["id"] for g in page if isinstance(g, dict))
        if len(page) < 50:
            break
        offset += 50

    graph = _request("GET", f"{base}/api/permissions/graph", session)
    groups = graph.get("groups", {})

    # Graph keys are group IDs as strings. Find ones with no live group.
    orphaned = [gid for gid in groups if int(gid) not in existing]
    if not orphaned:
        print("No orphaned group rows in the permissions graph. Nothing to do.")
        return

    print(f"Orphaned group IDs in graph (no matching group): {sorted(orphaned, key=int)}")
    for gid in orphaned:
        print(f"  - group {gid}: {json.dumps(groups[gid])}")

    if not apply:
        print("\nDry run. Re-run with --apply to remove these and PUT the cleaned graph.")
        return

    for gid in orphaned:
        del groups[gid]

    # PUT requires the current revision so Metabase can detect conflicts.
    _request("PUT", f"{base}/api/permissions/graph", session, body=graph)
    print(f"\nRemoved {len(orphaned)} orphaned group(s) and saved the cleaned graph.")


if __name__ == "__main__":
    main()
