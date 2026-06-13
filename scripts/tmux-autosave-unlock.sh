#!/bin/bash
# Mark the current tmux server as restored and safe for autosave.

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
UNLOCKED_SERVER_FILE="${TMUX_AUTOSAVE_UNLOCKED_SERVER:-$STATE_DIR/unlocked-server}"

mkdir -p "$STATE_DIR"

if ! command -v tmux >/dev/null 2>&1 || ! tmux list-sessions >/dev/null 2>&1; then
  echo "tmux server not found" >&2
  exit 1
fi

pid="$(tmux display-message -p '#{pid}')"
start_time="$(tmux display-message -p '#{start_time}')"
printf '%s:%s\n' "$pid" "$start_time" > "$UNLOCKED_SERVER_FILE"

tmux set-option -gq @tmux_autosave_error "" 2>/dev/null || true

echo "tmux autosave unlocked for server $pid:$start_time"
