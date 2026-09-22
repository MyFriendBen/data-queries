#!/usr/bin/env python3
"""Render Metabase card SQL to files that `bq query --dry_run` can check.

Usage:
    GCP_PROJECT_ID=mfb-data python3 dashboards/scripts/extract_card_sql.py \
        [dashboards/heat_pump_energy_journey.tf] [/tmp/hp-card-sql]

    for f in /tmp/hp-card-sql/*.sql; do
      bq query --dry_run --use_legacy_sql=false --project_id=mfb-data < "$f" \
        >/dev/null && echo "ok   $(basename $f)" || echo "FAIL $(basename $f)"
    done


Metabase native SQL is validated by nothing before it reaches the UI, so a
syntax or column error only shows up as a broken card. This resolves the
Terraform interpolations and the Metabase template syntax so BigQuery can parse
each card for real.

Two variants per card, because they render to different SQL:
  .unset.sql  every [[optional block]] removed  (no dashboard filter applied)
  .set.sql    every block kept, {{tag}} replaced with a literal
"""
import os, re, sys, pathlib

TF = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dashboards/heat_pump_energy_journey.tf")
OUT = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/hp-card-sql")
PROJECT = os.environ.get("GCP_PROJECT_ID", "GCP_PROJECT_ID")
DATASET = os.environ.get("BQ_DATASET", "analytics")

LOCALS = {
    "local.bq_dataset": f"{PROJECT}.{DATASET}",
    "local.hp_state_filter": "screener_state = 'cesn'",
    "local.screener_analytics_epoch": "2026-07-29",
    "local.hp_min_group_size": "5",
    "local.hp_min_mom_base": "10",
}
SUPPRESS = (
    "[[AND {{income_band}} IS NOT NULL AND __N__ >= 5]]\n"
    "[[AND {{region}} IS NOT NULL AND __N__ >= 5]]\n"
    "[[AND {{utility}} IS NOT NULL AND __N__ >= 5]]\n"
    "[[AND {{below_200}} IS NOT NULL AND __N__ >= 5]]"
)
TAG_VALUES = {
    "start_date": "'2026-01-01'", "end_date": "'2026-12-31'",
    "income_band": "'Below 100% FPL'", "region": "'DRCOG'",
    "utility": "'Xcel'", "below_200": "'Below 200% FPL'",
}

text = TF.read_text()
blocks = re.findall(r"^  (hp_sql_[a-z_0-9]+) = <<-SQL\n(.*?)\n  SQL$", text, re.M | re.S)
if not blocks:
    sys.exit("no hp_sql_* heredocs found")

OUT.mkdir(parents=True, exist_ok=True)
for name, body in blocks:
    # ${replace(local.hp_suppress_when_segmented, "__N__", "<expr>")}
    body = re.sub(
        r'\$\{replace\(local\.hp_suppress_when_segmented,\s*"__N__",\s*"(.*?)"\)\}',
        lambda m: SUPPRESS.replace("__N__", m.group(1)), body)
    for k, v in LOCALS.items():
        body = body.replace("${" + k + "}", v)
    leftover = re.findall(r"\$\{[^}]+\}", body)
    if leftover:
        print(f"  !! {name}: unresolved {sorted(set(leftover))}")

    unset = re.sub(r"\[\[.*?\]\]", "", body, flags=re.S)
    kept = re.sub(r"\[\[(.*?)\]\]", r"\1", body, flags=re.S)
    for tag, val in TAG_VALUES.items():
        kept = kept.replace("{{" + tag + "}}", val)
    if "{{" in kept:
        stray = set(re.findall(r"\{\{(\w+)\}\}", kept))
        print("  !! " + name + ": unreplaced tag " + str(stray))

    (OUT / f"{name}.unset.sql").write_text(unset.strip() + "\n")
    (OUT / f"{name}.set.sql").write_text(kept.strip() + "\n")
    print(f"  {name}")
print(f"\n{len(blocks)} cards -> {OUT}")
