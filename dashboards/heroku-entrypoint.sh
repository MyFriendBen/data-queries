#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=$PORT

# Run Metabase jar directly
cd /app
exec java -jar metabase.jar
