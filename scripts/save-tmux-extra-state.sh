#!/bin/bash
# save-tmux-extra-state.sh — Hook target for tmux-resurrect/continuum saves.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
status=0

"$SCRIPTS_DIR/save-ai-sessions.sh" || status=$?
"$SCRIPTS_DIR/save-mosh-sessions.sh" || status=$?

exit "$status"
