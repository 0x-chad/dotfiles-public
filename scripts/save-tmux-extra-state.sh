#!/bin/bash
# save-tmux-extra-state.sh — Hook target for tmux-resurrect/continuum saves.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
ERROR_FILE="${TMUX_AUTOSAVE_EXTRA_ERROR_FILE:-$STATE_DIR/extra-state-error}"
status=0
errors=()

mkdir -p "$STATE_DIR"

if ! "$SCRIPTS_DIR/save-ai-sessions.sh"; then
  status=$?
  [ "$status" -eq 0 ] && status=1
  errors+=("AI session save failed")
fi
if ! "$SCRIPTS_DIR/save-mosh-sessions.sh"; then
  mosh_status=$?
  [ "$mosh_status" -eq 0 ] && mosh_status=1
  [ "$status" -eq 0 ] && status="$mosh_status"
  errors+=("mosh session save failed")
fi

if [ "$status" -eq 0 ]; then
  rm -f "$ERROR_FILE"
else
  message="$(IFS='; '; echo "${errors[*]}")"
  tmp_error="${ERROR_FILE}.tmp.$$"
  printf '%s\n' "$message" > "$tmp_error"
  mv "$tmp_error" "$ERROR_FILE"
fi

exit "$status"
