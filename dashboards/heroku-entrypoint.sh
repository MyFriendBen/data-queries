#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=$PORT

# Heroku rotates the managed Postgres add-on's credentials and updates only
# DATABASE_URL. Deriving the connection here keeps Metabase pointed at the
# live database instead of a snapshot of the credentials.
export MB_DB_TYPE=postgres
export MB_DB_CONNECTION_URI="${DATABASE_URL}?sslmode=require"

# Bound the heap to the dyno's quota. Left unset, the JVM sizes the heap from
# the host's memory rather than the dyno limit and Heroku reports R14.
JAVA_HEAP="${JAVA_HEAP:--Xmx1900m}"

# Run Metabase jar directly
cd /app
exec java $JAVA_HEAP -XX:+UseG1GC -jar metabase.jar
