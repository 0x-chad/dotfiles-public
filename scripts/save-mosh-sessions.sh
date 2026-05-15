#!/bin/bash
# save-mosh-sessions.sh — Save mosh panes as explicit fallback restore commands.

set -euo pipefail

OUTPUT_FILE="${TMUX_MOSH_SESSIONS_FILE:-$HOME/.tmux-mosh-sessions.json}"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

children_of() {
  pgrep -P "$1" 2>/dev/null || true
}

process_tree() {
  local root="$1" child
  echo "$root"
  for child in $(children_of "$root"); do
    process_tree "$child"
  done
}

ps_args() {
  ps -p "$1" -o command= 2>/dev/null || true
}

mosh_restore_command() {
  local args="$1"
  args="${args#*-#}"
  args="${args%|*}"
  args="$(printf '%s' "$args" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$args" ] || return 1
  printf 'mosh %s\n' "$args"
}

find_mosh_command() {
  local pane_pid="$1" pid args command
  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue
    case "$args" in
      *mosh-client*)
        command=$(mosh_restore_command "$args" || true)
        if [ -n "$command" ]; then
          printf '%s\n' "$command"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

append_entry() {
  local tmpfile="$1" sess_name="$2" win_idx="$3" win_name="$4" pane_idx="$5"
  local pane_id="$6" pane_path="$7" command="$8"
  local entry

  entry=$(jq -n \
    --arg tmux_session "$sess_name" \
    --arg window_index "$win_idx" \
    --arg window_name "$win_name" \
    --arg pane_index "$pane_idx" \
    --arg pane_id "$pane_id" \
    --arg cwd "$pane_path" \
    --arg command "$command" \
    '{
      tmux_session: $tmux_session,
      window_index: ($window_index | tonumber),
      window_name: $window_name,
      pane_index: ($pane_index | tonumber),
      pane_id: $pane_id,
      cwd: $cwd,
      command: $command
    }')

  jq --argjson e "$entry" '. + [$e]' "$tmpfile" > "$tmpfile.next"
  mv "$tmpfile.next" "$tmpfile"
}

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile" "$tmpfile.next"' EXIT
echo "[]" > "$tmpfile"

total=0
saved=0

while IFS='|' read -r sess_name win_idx win_name pane_idx pane_pid pane_path pane_id; do
  command=$(find_mosh_command "$pane_pid" || true)
  [ -z "$command" ] && continue

  total=$((total + 1))
  echo "  OK   $sess_name/$win_name [$pane_id] $command"
  append_entry "$tmpfile" "$sess_name" "$win_idx" "$win_name" "$pane_idx" "$pane_id" "$pane_path" "$command"
  saved=$((saved + 1))
done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_pid}|#{pane_current_path}|#{pane_id}')

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "DRY RUN — identified $saved mosh session(s)."
  exit 0
fi

cp "$tmpfile" "$OUTPUT_FILE"

echo ""
echo "Saved $saved/$total mosh sessions to $OUTPUT_FILE"
