#!/bin/bash
# Mark autosave unsafe until tmux restore has run.

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
RESTORE_LOCK_FILE="${TMUX_AUTOSAVE_RESTORE_LOCK:-$STATE_DIR/restore-required}"

mkdir -p "$STATE_DIR"
{
  date '+%Y-%m-%d %H:%M:%S %Z'
  echo "autosave locked until restore-tmux.sh completes"
} > "$RESTORE_LOCK_FILE"

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux set-option -gq @tmux_autosave_error "restore lock active; run restore-tmux.sh" 2>/dev/null || true
  tmux set-option -gq status 2 2>/dev/null || true
fi

echo "tmux autosave locked: $RESTORE_LOCK_FILE"
