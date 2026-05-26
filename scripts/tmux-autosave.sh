#!/bin/bash
# tmux-autosave.sh - external scheduler entrypoint for tmux-resurrect saves.

set -uo pipefail

export PATH="$HOME/scripts:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_FILE="${TMUX_AUTOSAVE_LOG:-$HOME/.local/state/tmux-autosave.log}"
LOCK_DIR="${TMPDIR:-/tmp}/tmux-autosave-$(id -u).lock"

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

echo "[$(timestamp)] start"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(timestamp)] already running"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if ! command -v tmux >/dev/null 2>&1; then
  echo "[$(timestamp)] tmux not found"
  exit 0
fi

if ! tmux list-sessions >/dev/null 2>&1; then
  echo "[$(timestamp)] no tmux server"
  exit 0
fi

status=0
save_script="$(tmux show-option -gqv @resurrect-save-script-path 2>/dev/null || true)"
if [ -z "$save_script" ]; then
  save_script="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
fi

resurrect_dir="$(tmux show-option -gqv @resurrect-dir 2>/dev/null || true)"
if [ -z "$resurrect_dir" ]; then
  if [ -d "$HOME/.tmux/resurrect" ]; then
    resurrect_dir="$HOME/.tmux/resurrect"
  else
    resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
  fi
fi
last_link="$resurrect_dir/last"
old_last=""
if [ -L "$last_link" ]; then
  old_last="$(readlink "$last_link" || true)"
fi

if [ -x "$save_script" ]; then
  "$save_script" quiet || status=$?
  if [ "$status" -ne 0 ]; then
    echo "[$(timestamp)] tmux-resurrect save failed: $status"
  fi
else
  echo "[$(timestamp)] tmux-resurrect save script missing: $save_script"
  status=127
fi

new_last=""
new_last_path=""
if [ -L "$last_link" ]; then
  new_last="$(readlink "$last_link" || true)"
  new_last_path="$resurrect_dir/$new_last"
fi
if [ -n "$new_last_path" ] && [ -f "$new_last_path" ]; then
  if [ "$(wc -c < "$new_last_path")" -lt 1000 ] || ! grep -q '^pane' "$new_last_path"; then
    echo "[$(timestamp)] invalid tmux-resurrect snapshot: $new_last_path"
    if [ -n "$old_last" ] && [ -f "$resurrect_dir/$old_last" ]; then
      ln -sfn "$old_last" "$last_link"
      echo "[$(timestamp)] restored last link to $old_last"
    fi
    [ "$status" -eq 0 ] && status=1
  fi
fi

extra_state="$HOME/scripts/save-tmux-extra-state.sh"
if [ -x "$extra_state" ]; then
  "$extra_state" || {
    extra_status=$?
    echo "[$(timestamp)] extra state save failed: $extra_status"
    [ "$status" -eq 0 ] && status="$extra_status"
  }
else
  echo "[$(timestamp)] extra state script missing: $extra_state"
fi

echo "[$(timestamp)] done status=$status"
exit "$status"
