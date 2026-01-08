#!/bin/bash

# Metabase Development Setup Script
# Starts Metabase containers and checks if initial setup is complete

set -e

echo "Starting Metabase development environment..."

# Use METABASE_URL from env or default to localhost for dev
METABASE_URL="${METABASE_URL:-http://localhost:3001}"
echo "Metabase URL: $METABASE_URL"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

# Source environment variables
set -a
source .env
set +a

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

# Use METABASE_URL from env or default to localhost
METABASE_URL="${METABASE_URL:-http://localhost:3001}"

# Check if setup is already complete
if curl -f -s "$METABASE_URL/api/session/properties" | grep -q '"has-user-setup":true'; then
    echo "Metabase is already configured."
    echo ""
    echo "Next step: Import permissions graph and configure resources"
    echo "Run: cd ../terraform && ./import-metabase-permissions.sh"
else
    echo ""
    echo "Metabase needs initial setup. Please complete the setup wizard at:"
    echo "   $METABASE_URL"
    echo ""
    echo "After completing the setup wizard, run:"
    echo "   cd ../terraform && ./import-metabase-permissions.sh"
    exit 0
fi

echo ""
echo "Access your Metabase instance at: $METABASE_URL"