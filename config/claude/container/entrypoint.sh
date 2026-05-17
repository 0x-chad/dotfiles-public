#!/bin/bash
# Source secrets
. ~/.secrets

# Extract OAuth token from credentials file if not already set
if [[ -z "$CLAUDE_CODE_OAUTH_TOKEN" && -f ~/.claude/.credentials.json ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
fi

# Start virtual display and noVNC if NOVNC=1
if [[ "$NOVNC" == "1" ]]; then
  export DISPLAY=:99
  Xvfb :99 -screen 0 1280x720x24 &
  sleep 1
  fluxbox &
  x11vnc -display :99 -forever -shared -rfbport 5900 -bg -nopw -q
  /usr/share/novnc/utils/novnc_proxy --listen 6080 --vnc localhost:5900 &
  echo "noVNC running at http://localhost:6080"
fi

exec "$@"
