#!/bin/bash
# Clear the restore-required autosave lock.

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
RESTORE_LOCK_FILE="${TMUX_AUTOSAVE_RESTORE_LOCK:-$STATE_DIR/restore-required}"

rm -f "$RESTORE_LOCK_FILE"

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux set-option -gq @tmux_autosave_error "" 2>/dev/null || true
fi

echo "tmux autosave unlocked"
