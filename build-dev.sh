#!/bin/bash
# Build dev container
set -e

cd "$(dirname "$0")"

# Copy secrets for build (API keys for PAL MCP)
cp ~/.secrets ./secrets

# Build
docker build -t claude-dev .

# Cleanup
rm -f ./secrets

# Create persistent volume for credentials if it doesn't exist
docker volume create claude-creds 2>/dev/null || true

echo ""
echo "Done! Run with:"
echo "  docker run -it --rm -v claude-creds:/home/testuser/.claude claude-dev"
echo ""
echo "First run will require login. Credentials persist in 'claude-creds' volume."
