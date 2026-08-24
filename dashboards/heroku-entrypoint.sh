#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=$PORT

# The app DB comes from the MB_DB_* config vars. Those are a hand-copied
# snapshot of the managed Postgres add-on's credentials, which Heroku rotates
# while updating only DATABASE_URL — so they can go stale. Deriving them here
# instead requires converting DATABASE_URL to JDBC form; Metabase does not
# parse postgres:// URLs, and assuming otherwise has crashed this app before
# (see DEPLOYMENT_PLAN.md, "Metabase Database Connection"). Needs a staging
# test before it replaces the config vars.

# Bound the heap to the dyno's quota. Left unset, the JVM sizes the heap from
# the host's memory rather than the dyno limit and Heroku reports R14.
#
# Each flag must be space-separated and self-contained, e.g. "-Xmx2g -Xms2g" —
# "-Xmx 2g" is not valid to the JVM. The expansion below is deliberately
# unquoted so those flags split into separate arguments; `set -f` keeps a stray
# glob character from expanding to repository paths on the way through.
JAVA_HEAP="${JAVA_HEAP:--Xmx1900m}"
set -f

# Run Metabase jar directly
cd /app
exec java $JAVA_HEAP -XX:+UseG1GC -jar metabase.jar
