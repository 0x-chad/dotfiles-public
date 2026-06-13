#!/bin/bash
# tmux-autosave.sh - guarded tmux-resurrect save for tmux-continuum or cron.

set -uo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

export PATH="$HOME/scripts:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_FILE="${TMUX_AUTOSAVE_LOG:-$HOME/.local/state/tmux-autosave.log}"
LOCK_DIR="${TMPDIR:-/tmp}/tmux-autosave-$(id -u).lock"
STATE_DIR="${TMUX_AUTOSAVE_STATE_DIR:-$HOME/.local/state/tmux-autosave}"
UNLOCKED_SERVER_FILE="${TMUX_AUTOSAVE_UNLOCKED_SERVER:-$STATE_DIR/unlocked-server}"
FORCE_SAVE="${TMUX_AUTOSAVE_FORCE:-0}"
UPSTREAM_SAVE_SCRIPT="${TMUX_AUTOSAVE_RESURRECT_SAVE_SCRIPT:-}"

for arg in "$@"; do
  case "$arg" in
    --force) FORCE_SAVE=1 ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$STATE_DIR"
exec >>"$LOG_FILE" 2>&1

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

snapshot_field_count() {
  local field="$1"
  local file="$2"
  awk -v field="$field" 'index($0, field "\t") == 1 { count++ } END { print count + 0 }' "$file" 2>/dev/null
}

is_truthy() {
  case "${1:-}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

valid_snapshot() {
  local file="$1"
  local expected_panes="$2"
  local expected_windows="$3"
  local bytes pane_rows window_rows

  [ -n "$file" ] || return 1
  [ -f "$file" ] || return 1

  bytes="$(wc -c < "$file" 2>/dev/null || echo 0)"
  [ "$bytes" -ge 1000 ] || return 1

  pane_rows="$(snapshot_field_count pane "$file")"
  window_rows="$(snapshot_field_count window "$file")"

  [ "$pane_rows" -ge "$expected_panes" ] || return 1
  [ "$window_rows" -ge "$expected_windows" ] || return 1
}

valid_structural_snapshot() {
  local file="$1"
  [ -n "$file" ] || return 1
  [ -f "$file" ] || return 1
  [ "$(wc -c < "$file" 2>/dev/null || echo 0)" -ge 1000 ] || return 1
  [ "$(snapshot_field_count pane "$file")" -ge 1 ] || return 1
  [ "$(snapshot_field_count window "$file")" -ge 1 ] || return 1
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  path="${path//\$HOME/$HOME}"
  path="${path//\$HOSTNAME/$(hostname)}"
  echo "$path"
}

current_server_id() {
  local pid start_time
  pid="$(tmux display-message -p '#{pid}' 2>/dev/null || true)"
  start_time="$(tmux display-message -p '#{start_time}' 2>/dev/null || true)"
  [ -n "$pid" ] && [ -n "$start_time" ] || return 1
  echo "$pid:$start_time"
}

restore_old_last() {
  local resurrect_dir="$1"
  local last_link="$2"
  local old_last="$3"

  if [ -n "$old_last" ] && valid_structural_snapshot "$resurrect_dir/$old_last"; then
    ln -sfn "$old_last" "$last_link"
    echo "[$(timestamp)] restored last link to $old_last"
  else
    echo "[$(timestamp)] no previous valid last link to restore"
  fi
}

mark_save_failed() {
  local message="$1"
  local current_status forced_status

  current_status="$(tmux show-option -gqv status 2>/dev/null || true)"
  forced_status="$(tmux show-option -gqv @tmux_autosave_forced_status 2>/dev/null || true)"
  if [ "$current_status" != "2" ] && [ -z "$forced_status" ]; then
    tmux set-option -gq @tmux_autosave_forced_status "$current_status" 2>/dev/null || true
  fi

  tmux set-option -gq @tmux_autosave_error "$message" 2>/dev/null || true
  # A persistent tmux warning needs the status bar visible; restore the user's
  # previous status setting after the next successful validated save.
  tmux set-option -gq status 2 2>/dev/null || true
  tmux display-message "tmux autosave failed: $message" 2>/dev/null || true
}

mark_save_ok() {
  local forced_status

  tmux set-option -gq @tmux_autosave_error "" 2>/dev/null || true
  forced_status="$(tmux show-option -gqv @tmux_autosave_forced_status 2>/dev/null || true)"
  if [ -n "$forced_status" ]; then
    tmux set-option -gq status "$forced_status" 2>/dev/null || true
  fi
  tmux set-option -gq @tmux_autosave_forced_status "" 2>/dev/null || true
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

expected_panes="$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
expected_windows="$(tmux list-windows -a -F '#{window_id}' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${expected_panes:-0}" -lt 1 ] || [ "${expected_windows:-0}" -lt 1 ]; then
  echo "[$(timestamp)] no panes/windows to save"
  exit 0
fi

save_script="$(tmux show-option -gqv @resurrect-save-script-path 2>/dev/null || true)"
configured_upstream="$(tmux show-option -gqv @tmux_autosave_resurrect_save_script 2>/dev/null || true)"
if [ -n "$UPSTREAM_SAVE_SCRIPT" ]; then
  save_script="$UPSTREAM_SAVE_SCRIPT"
elif [ -n "$configured_upstream" ]; then
  save_script="$configured_upstream"
fi

case "$save_script" in
  "$0"|"$HOME/scripts/tmux-autosave.sh"|*/tmux-autosave.sh) save_script="" ;;
esac

if [ -z "$save_script" ]; then
  save_script="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
fi
save_script="$(expand_path "$save_script")"

resurrect_dir="$(tmux show-option -gqv @resurrect-dir 2>/dev/null || true)"
if [ -z "$resurrect_dir" ]; then
  if [ -d "$HOME/.tmux/resurrect" ]; then
    resurrect_dir="$HOME/.tmux/resurrect"
  else
    resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
  fi
fi
resurrect_dir="$(expand_path "$resurrect_dir")"

last_link="$resurrect_dir/last"
old_last=""
if [ -L "$last_link" ]; then
  old_last="$(readlink "$last_link" || true)"
fi
old_last_path=""
if [ -n "$old_last" ]; then
  old_last_path="$resurrect_dir/$old_last"
fi

if [ -n "$old_last_path" ] && valid_structural_snapshot "$old_last_path" && ! is_truthy "$FORCE_SAVE"; then
  server_id="$(current_server_id || true)"
  unlocked_server=""
  [ -f "$UNLOCKED_SERVER_FILE" ] && unlocked_server="$(head -n 1 "$UNLOCKED_SERVER_FILE" 2>/dev/null || true)"
  if [ -z "$server_id" ] || [ "$server_id" != "$unlocked_server" ]; then
    message="$(timestamp): tmux server not restored; run ~/scripts/restore-tmux.sh"
    echo "[$(timestamp)] $message current=${server_id:-unknown} unlocked=${unlocked_server:-none}"
    mark_save_failed "$message"
    exit 2
  fi
fi

status=0
if [ -x "$save_script" ]; then
  quoted_save_script="$(shell_quote "$save_script")"
  tmux run-shell "exec $quoted_save_script quiet" || status=$?
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

if valid_snapshot "$new_last_path" "$expected_panes" "$expected_windows"; then
  pane_rows="$(snapshot_field_count pane "$new_last_path")"
  window_rows="$(snapshot_field_count window "$new_last_path")"
  bytes="$(wc -c < "$new_last_path" 2>/dev/null || echo 0)"
  echo "[$(timestamp)] validated snapshot: $new_last panes=$pane_rows/$expected_panes windows=$window_rows/$expected_windows bytes=$bytes"
  if [ "$status" -eq 0 ]; then
    mark_save_ok
  else
    mark_save_failed "$(timestamp): save command failed status $status"
  fi
else
  echo "[$(timestamp)] invalid tmux-resurrect snapshot: ${new_last_path:-missing}"
  restore_old_last "$resurrect_dir" "$last_link" "$old_last"
  mark_save_failed "$(timestamp): invalid snapshot"
  [ "$status" -eq 0 ] && status=1
fi

echo "[$(timestamp)] done status=$status"
exit "$status"
