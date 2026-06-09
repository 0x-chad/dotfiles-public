#!/bin/bash
# restore-mosh-sessions.sh — Relaunch missing mosh panes from fallback manifest.

set -euo pipefail

INPUT_FILE="${TMUX_MOSH_SESSIONS_FILE:-$HOME/.tmux-mosh-sessions.json}"
DRY_RUN=false
DELAY="${DELAY:-1}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

if [ ! -f "$INPUT_FILE" ]; then
  echo "No mosh session manifest found at $INPUT_FILE"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

find_target_pane() {
  local tmux_session="$1" win_idx="$2" win_name="$3" pane_idx="$4"
  local found_win

  if tmux list-panes -t "=${tmux_session}:${win_idx}" -F '#{pane_index}' 2>/dev/null | grep -qx "$pane_idx"; then
    echo "=${tmux_session}:${win_idx}.${pane_idx}"
    return 0
  fi

  found_win=$(tmux list-windows -t "=$tmux_session" -F '#{window_index}|#{window_name}' 2>/dev/null \
    | grep "|${win_name}$" | head -1 | cut -d'|' -f1)
  if [ -n "$found_win" ] &&
     tmux list-panes -t "=${tmux_session}:${found_win}" -F '#{pane_index}' 2>/dev/null | grep -qx "$pane_idx"; then
    echo "=${tmux_session}:${found_win}.${pane_idx}"
    return 0
  fi

  return 1
}

pane_has_mosh() {
  local target="$1" pane_pid pid args
  pane_pid=$(tmux list-panes -t "$target" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -n "$pane_pid" ] || return 1

  for pid in "$pane_pid" $(pgrep -P "$pane_pid" 2>/dev/null || true); do
    args=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case "$args" in
      *mosh-client*) return 0 ;;
    esac
  done

  return 1
}

safe_to_replace() {
  local target="$1" current
  current=$(tmux list-panes -t "$target" -F '#{pane_current_command}' 2>/dev/null | head -1)
  case "$current" in
    ""|bash|zsh|sh|fish|login|tmux|mosh-client) return 0 ;;
  esac
  return 1
}

echo "Restoring missing mosh sessions from $INPUT_FILE"
[ "$DRY_RUN" = true ] && echo "(DRY RUN — no commands will be sent)"
echo ""

total=$(jq length "$INPUT_FILE")
restored=0
skipped=0

if [ "$total" -eq 0 ]; then
  echo "No mosh sessions saved."
  echo ""
  echo "Restored 0/0 mosh sessions (0 skipped)."
  exit 0
fi

for i in $(seq 0 $((total - 1))); do
  tmux_session=$(jq -r ".[$i].tmux_session" "$INPUT_FILE")
  win_idx=$(jq -r ".[$i].window_index" "$INPUT_FILE")
  win_name=$(jq -r ".[$i].window_name" "$INPUT_FILE")
  pane_idx=$(jq -r ".[$i].pane_index" "$INPUT_FILE")
  command=$(jq -r ".[$i].command" "$INPUT_FILE")
  label="$tmux_session/$win_name"

  case "$command" in
    mosh\ *) ;;
    *)
      echo "  SKIP $label — saved command is not mosh"
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  target=$(find_target_pane "$tmux_session" "$win_idx" "$win_name" "$pane_idx" || true)
  if [ -z "$target" ]; then
    echo "  SKIP $label — pane not found"
    skipped=$((skipped + 1))
    continue
  fi

  if pane_has_mosh "$target"; then
    echo "  SKIP $label — already running"
    skipped=$((skipped + 1))
    continue
  fi

  if ! safe_to_replace "$target"; then
    current=$(tmux list-panes -t "$target" -F '#{pane_current_command}' 2>/dev/null | head -1)
    echo "  SKIP $label — pane has '$current' running"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  OK   $label -> $command"
  else
    echo "  OK   $label"
    tmux send-keys -t "$target" C-c
    tmux send-keys -t "$target" "$command" Enter
    sleep "$DELAY"
  fi
  restored=$((restored + 1))
done

echo ""
echo "Restored $restored/$total mosh sessions ($skipped skipped)."
