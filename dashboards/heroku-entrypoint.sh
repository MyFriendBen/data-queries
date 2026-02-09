#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=${PORT:-3000}

# Decode BigQuery service account key from base64 env var
if [ -n "$BIGQUERY_SA_KEY_BASE64" ]; then
    echo "$BIGQUERY_SA_KEY_BASE64" | base64 -d > /tmp/bigquery-sa-key.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/bigquery-sa-key.json
fi

exec /app/run_metabase.sh
