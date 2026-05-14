## Context & Motivation

<!-- Required: Why is this change needed? Link to issue, describe the problem, or explain the goal -->

- Fixes #[issue-number]
- Related PR: [link if applicable]

## Changes Made

<!-- Required: What specifically changed? Be concrete and specific -->
<!-- Examples: dbt models added/modified, Terraform resources updated, Metabase container change, scripts added -->

- ...

## Testing

<!-- Steps needed to test this PR locally -->

- dbt models to run: `dbt run --select <model_name>` (or `dbt build` for tests too)
- Terraform plan reviewed: <!-- paste or link to plan output if applicable -->
- Local Metabase tested via docker-compose: yes / no / N/A
- Other manual testing steps:

## Deployment

<!--
Merging to main automatically applies Terraform changes to production.
Metabase container rebuilds and out-of-band dbt runs require manual steps — note them here.
-->

- [ ] Metabase container rebuild/redeploy needed: yes / no
- [ ] dbt production run needed (outside nightly cron): yes / no
- [ ] Other post-deployment steps:

## Notes for Reviewers

<!-- Optional: Anything specific you want reviewers to focus on or be aware of -->

- Known limitations:
- Future considerations:
