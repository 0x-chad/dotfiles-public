#!/bin/bash
# Source secrets to set env vars (including CLAUDE_CODE_OAUTH_TOKEN)
. ~/.secrets
exec "$@"
