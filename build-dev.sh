#!/bin/bash
# Build dev container with secrets baked in
set -e

cd "$(dirname "$0")"

# Copy secrets for build (not committed to git)
cp ~/.secrets ./secrets

# Build
docker build -t claude-dev .

# Cleanup
rm -f ./secrets

echo ""
echo "Done! Run with: docker run -it --rm claude-dev"
