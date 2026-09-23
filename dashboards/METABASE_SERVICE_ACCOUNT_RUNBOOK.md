# Metabase CI Service Account Runbook

Replacing the personal Metabase account that CI authenticates as with a dedicated
service account.

## Status

**Parts 0–4 completed 2026-09-08.** Kept below for reference and for the next time
this needs doing.

| Item | Value |
|---|---|
| Service account | `service-accounts@myfriendben.org`, Metabase user **id 694** |
| Groups | All Users, Administrators (superuser confirmed) |
| Password set | 2026-09-08 via `PUT /api/user/694/password` (HTTP 204) |
| Verified | login OK, 21 permission groups, 11 databases |
| `METABASE_ADMIN_EMAIL` | updated 2026-09-08 17:46 UTC |
| `METABASE_ADMIN_PASSWORD` | updated 2026-09-08 17:49 UTC |

Part 5 verification is folded into the team's normal Metabase deploy runbook
(dbt-nightly full refresh → scale up → terraform apply → scale down → `heroku ps`).
Part 6 follow-ups remain open.

## Background

All four production workflows in this repo log in to Metabase as a **human's**
account, read from the `production` environment's `METABASE_ADMIN_EMAIL` variable
and `METABASE_ADMIN_PASSWORD` secret:

| Workflow | What it does with the session |
|---|---|
| `terraform-apply.yml` | Provider auth + `data.external.metabase_ids` |
| `terraform-plan.yml` | Same, plan only |
| `dbt-nightly.yml` | Triggers schema sync on each database |
| `dbt-on-merge.yml` | Same |

On **2026-08-31 21:57 UTC** an offboarding pass deactivated `josh@myfriendben.org`
(Metabase user id 1), which was that account. Every workflow above started failing
to authenticate:

```
clojure.lang.ExceptionInfo: Your account is disabled. Please contact your administrator.
{:status-code 401, ...}
```

`terraform-apply` fails loudly. The two dbt workflows swallow it (`::warning::` then
`exit 0`) and still report green, which is why it went unnoticed for four days.

This runbook removes the dependency on any individual's account so the next
offboarding doesn't break the pipeline.

## Environment facts

Confirmed against production on 2026-09-04:

- Metabase **v0.56.19** (OSS) at `https://mfb-metabase-production-baf31df893fc.herokuapp.com`
- Password auth only — no Google auth, no SSO
- SMTP **is** configured; sends from `screener@myfriendben.org`
- Password policy: **minimum 6 characters, at least 1 digit**
- `Administrators` is permission group **id 2**
- Terraform ignores group 2 (`local.ignored_group_ids = concat([2], unmanaged_group_ids)`
  in `permissions.tf`), so adding an admin user is inert for the permissions graph —
  no Terraform change is needed anywhere in this runbook

---

## Part 0 — Decide the address

Recommended: **`service-accounts@myfriendben.org`**

It should be a real, deliverable address rather than a fiction, because Metabase
will send an invite email to it on creation and may send password-reset or system
mail to it later. It does **not** need to be a mailbox anyone actively reads, and
you will **not** need to open the invite email — Part 2 sets the password directly
via the admin API.

Point it at a group/alias rather than a person, so it survives the next offboarding.
That is the entire purpose of this exercise.

## Part 1 — Create the mail alias

In Google Workspace admin (or whoever hosts `myfriendben.org` mail), create
`service-accounts@myfriendben.org` as a **group or alias** delivering to the
data/engineering group — not to a single person's inbox.

Do this *before* Part 2. Metabase inserts the user and then publishes the invite
email as an event inside the request transaction; if SMTP hard-fails on an
undeliverable address the create call can error out. Having the alias exist first
sidesteps the question entirely.

Verify it accepts mail before continuing.

## Part 2 — Create the Metabase user and set its password

You need to be an active Metabase superuser to do this. As of 2026-09-04
`elliott@myfriendben.org` (id 67) is one.

**Handle the password carefully.** Generate it, put it straight into a password
manager, and enter it into shells via `read -s` so it never lands in
`~/.zsh_history`. Do not paste it into chat, tickets, or PR descriptions.

### 2a. Open a session as yourself

```bash
read -rs "?Your Metabase password: " MB_MY_PASS; echo   # zsh syntax
export MB_URL="https://mfb-metabase-production-baf31df893fc.herokuapp.com"
export MB_SESSION=$(curl -sf -X POST "$MB_URL/api/session" \
  -H "Content-Type: application/json" \
  -d "$(jq -cn --arg u "elliott@myfriendben.org" --arg p "$MB_MY_PASS" \
        '{username:$u, password:$p}')" | jq -r '.id')
unset MB_MY_PASS
echo "session: ${MB_SESSION:0:8}…"
```

If `MB_SESSION` is empty or `null`, stop — your own login is the problem, not the
service account.

### 2b. Generate the service account password

```bash
export MB_SVC_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
echo "$MB_SVC_PASS"
```

Copy it into the password manager now, in the same entry you'll use for the GitHub
secret. A 32-character alphanumeric string satisfies the 6-char/1-digit policy with
room to spare.

### 2c. Create the user in the Administrators group

```bash
curl -sf -X POST "$MB_URL/api/user" \
  -H "Content-Type: application/json" \
  -H "X-Metabase-Session: $MB_SESSION" \
  -d '{
        "first_name": "MFB",
        "last_name": "Automation",
        "email": "service-accounts@myfriendben.org",
        "user_group_memberships": [{"id": 1}, {"id": 2}]
      }' | jq '{id, email, is_superuser, common_name}'
```

Group 1 is `All Users` (Metabase adds it regardless), group 2 is `Administrators`.
Terraform manages databases, the collection graph, and the permissions graph, so
the account genuinely needs superuser — a viewer/editor group is not enough.

Record the returned `id`:

```bash
export MB_SVC_ID=<id from the response>
```

An invite email goes to the alias at this point. Ignore it.

> `POST /api/user` accepts an optional `password` in its underlying schema, but the
> endpoint's own parameter list doesn't declare it, so whether it survives request
> validation is version-dependent. Don't rely on it — set the password explicitly in
> 2d, which is unambiguous.

### 2d. Set the password

```bash
curl -sf -X PUT "$MB_URL/api/user/$MB_SVC_ID/password" \
  -H "Content-Type: application/json" \
  -H "X-Metabase-Session: $MB_SESSION" \
  -d "$(jq -cn --arg p "$MB_SVC_PASS" '{password:$p}')" \
  -o /dev/null -w '%{http_code}\n'
```

Expect `200` or `204`. Superusers may reset any user's password without supplying
`old_password`, which is what makes the invite email unnecessary.

## Part 3 — Verify the service account can log in

Before touching GitHub, prove the credentials work — this is exactly the call CI makes:

```bash
curl -s -o /tmp/mb_svc_session.json -w '%{http_code}\n' \
  -X POST "$MB_URL/api/session" \
  -H "Content-Type: application/json" \
  -d "$(jq -cn --arg u "service-accounts@myfriendben.org" --arg p "$MB_SVC_PASS" \
        '{username:$u, password:$p}')"
```

Expect `200`. Then confirm it has the admin reach Terraform needs:

```bash
SVC=$(jq -r '.id' /tmp/mb_svc_session.json)
curl -s "$MB_URL/api/permissions/group" -H "X-Metabase-Session: $SVC" | jq 'length'
curl -s "$MB_URL/api/database" -H "X-Metabase-Session: $SVC" | jq '.total'
```

Both must return numbers, not an error object. `/api/permissions/group` is
superuser-only, so a successful response there is the real proof of admin rights.
Expect 11 databases.

Clean up:

```bash
curl -s -X DELETE "$MB_URL/api/session" -H "X-Metabase-Session: $SVC" -o /dev/null
rm -f /tmp/mb_svc_session.json
```

**Do not proceed to Part 4 until this passes.** Rotating the GitHub secret to a
credential you haven't tested just swaps one broken login for another.

## Part 4 — Update GitHub

Both values are scoped to the **`production` environment** (they are not repo-level
— `gh variable list --repo MyFriendBen/data-queries` returns nothing). All four
workflows declare `environment: production`, so this one change covers all of them.

```bash
gh variable set METABASE_ADMIN_EMAIL \
  --repo MyFriendBen/data-queries --env production \
  --body "service-accounts@myfriendben.org"
```

```bash
gh secret set METABASE_ADMIN_PASSWORD \
  --repo MyFriendBen/data-queries --env production
```

`gh secret set` with no `--body` prompts on stdin, so the password stays out of
shell history. Paste it from the password manager.

Confirm the variable took (the secret's value is not readable back, by design):

```bash
gh variable list --repo MyFriendBen/data-queries --env production | grep METABASE_ADMIN_EMAIL
gh secret list --repo MyFriendBen/data-queries --env production | grep METABASE_ADMIN_PASSWORD
```

The secret row should show today's `Updated` date.

## Part 5 — Verify the pipelines

### 5a. Terraform plan first

```bash
gh workflow run terraform-plan.yml --repo MyFriendBen/data-queries
```

Watch it: <https://github.com/MyFriendBen/data-queries/actions>

A green plan proves the provider *and* `data.external.metabase_ids` both
authenticate. As of 2026-09-04 there are no commits touching `dashboards/` since the
last successful apply on 2026-08-27, so **the plan should report no changes**. If it
proposes changes, stop and read them before applying — that's drift someone
introduced through the Metabase UI, not something this runbook caused.

### 5b. Terraform apply

Only if the plan is clean. Metabase needs the larger dyno for the apply:

```bash
heroku ps:resize web=performance-m --app mfb-metabase-production
```

Wait ~2 minutes for the restart to finish before dispatching. Metabase returns
`503 Service Unavailable` while it boots, and a too-early apply fails on that — this
is the failure seen on 2026-08-14 and 2026-08-27, distinct from the 401 this runbook
fixes. Confirm it's up first:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$MB_URL/api/health"
```

Expect `200`, then:

```bash
gh workflow run terraform-apply.yml --repo MyFriendBen/data-queries
```

Scale back down once it completes:

```bash
heroku ps:resize web=standard-2x --app mfb-metabase-production
```

```bash
heroku ps --app mfb-metabase-production
```

Performance-M bills ~$0.347/hr, so don't leave it up.

### 5c. dbt schema sync

```bash
gh workflow run dbt-nightly.yml --repo MyFriendBen/data-queries
```

This one reports success even when the Metabase step fails, so check the step
output rather than the run's overall status:

```bash
gh run view <run-id> --repo MyFriendBen/data-queries --log \
  | grep "Trigger Metabase schema sync" | grep -E "warning|Syncing database"
```

You want `Syncing database <id>…` lines and **no** `Failed to authenticate with
Metabase — skipping sync` warning.

## Part 6 — Follow-ups

Not required to unblock, but this incident exists because of them.

1. **Make the dbt workflows fail loudly.** In `dbt-nightly.yml` and
   `dbt-on-merge.yml`, change the auth-failure branch from `exit 0` to `exit 1`. A
   silently skipped sync reporting green is what hid this for four days.

2. **Audit for other personal-account dependencies.** `josh@myfriendben.org` is
   still `creator_id` on 853 cards and 11 dashboards. That's harmless for viewing
   and querying, and the account owns no active pulses or notifications — but it's
   worth checking whether any other automation anywhere authenticates as a person.

3. **Add Metabase to the offboarding checklist** with an explicit note that user id
   1 and any `*-automation@` account must not be deactivated without rotating the
   corresponding GitHub credentials first.

4. **Leave `josh@myfriendben.org` deactivated.** Reactivating it would unblock CI in
   thirty seconds and re-create the exact problem. It's not the fix.

## Rollback

If something in Parts 4–5 goes wrong and you need CI working immediately, revert
the two GitHub values to the previous account and reactivate it:

```bash
gh variable set METABASE_ADMIN_EMAIL \
  --repo MyFriendBen/data-queries --env production \
  --body "josh@myfriendben.org"
```

Reactivate via Metabase Admin → People, or:

```bash
curl -sf -X PUT "$MB_URL/api/user/1/reactivate" \
  -H "X-Metabase-Session: $MB_SESSION" -o /dev/null -w '%{http_code}\n'
```

You would also need the old password restored to `METABASE_ADMIN_PASSWORD`, so only
take this path if that value is still retrievable from the password manager.

Treat this strictly as a break-glass measure and re-attempt the service account
promptly — it puts a deactivated ex-employee's account back into production.
