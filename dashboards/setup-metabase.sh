#!/bin/bash

# Metabase Development Setup Script
# Starts Metabase containers and checks if initial setup is complete

set -e

echo "Starting Metabase development environment..."

# Use METABASE_PORT to construct URL (defaults to 3001)
METABASE_PORT="${METABASE_PORT:-3001}"
METABASE_URL="http://localhost:${METABASE_PORT}"
echo "Metabase URL: $METABASE_URL"

echo "Starting Metabase containers..."
docker compose up -d

echo "Waiting for Metabase to be ready..."
timeout=300
counter=0
while ! curl -f -s "$METABASE_URL/api/health" > /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "ERROR: Timeout waiting for Metabase to start"
        exit 1
    fi
    echo "   Still waiting... ($counter seconds)"
    sleep 5
    counter=$((counter + 5))
done

echo "Metabase is ready!"

# Check if setup is already complete
if curl -f -s "$METABASE_URL/api/session/properties" | grep -q '"has-user-setup":true'; then
    echo "Metabase is already configured."
    echo ""
    echo "Access your Metabase instance at: $METABASE_URL"
else
    echo ""
    echo "Metabase needs initial setup. Please complete the setup wizard at:"
    echo "   $METABASE_URL"
    echo ""
    echo "After completing the setup wizard, configure BigQuery and collections:"
    echo "   cd ../terraform && terraform apply"
    exit 0
fi