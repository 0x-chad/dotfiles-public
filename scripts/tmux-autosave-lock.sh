#!/bin/bash
# Clear the approved tmux server id so autosave blocks until restore runs.

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
UNLOCKED_SERVER_FILE="${TMUX_AUTOSAVE_UNLOCKED_SERVER:-$STATE_DIR/unlocked-server}"

mkdir -p "$STATE_DIR"
rm -f "$UNLOCKED_SERVER_FILE"

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux set-option -gq @tmux_autosave_error "tmux server not restored; run restore-tmux.sh" 2>/dev/null || true
  tmux set-option -gq status 2 2>/dev/null || true
fi

echo "tmux autosave server approval cleared"
