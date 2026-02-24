#!/bin/bash

# Load environment variables from .env file
# Usage: source load-env.sh

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Please create a .env file based on .env.example"
    return 1 2>/dev/null || exit 1
fi

# Load environment variables
echo "🔄 Loading environment variables from .env..."
set -a && source .env && set +a

echo "✅ Environment variables loaded successfully!"
