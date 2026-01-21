#!/bin/bash
# Source secrets
. ~/.secrets

# Extract OAuth token from credentials file if not already set
if [[ -z "$CLAUDE_CODE_OAUTH_TOKEN" && -f ~/.claude/.credentials.json ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
fi

exec "$@"
