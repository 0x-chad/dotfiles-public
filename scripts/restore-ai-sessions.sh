#!/bin/bash
# restore-ai-sessions.sh — Restore Claude/Codex sessions after reboot
# Run after tmux-resurrect has restored your tmux layout.
#
# Usage: ~/scripts/restore-ai-sessions.sh [--dry-run]
#
# Matches saved sessions to tmux panes by session_name + window_index + pane_index.
# Falls back to session_name + window_name + pane_index if window index doesn't match
# (handles tmux-resurrect reordering windows).

set -euo pipefail

INPUT_FILE="$HOME/.tmux-ai-sessions.json"
DRY_RUN=false
DELAY="${DELAY:-2}"  # seconds between launching sessions

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: $INPUT_FILE not found. Run save-ai-sessions.sh first."
  exit 1
fi

pane_label() {
  local sess="$1" win="$2" pidx="$3" widx="$4"
  local count
  count=$(tmux list-windows -t "$sess" -F '#{window_name}' 2>/dev/null | grep -cx "$win" || echo 0)
  local name="$sess/$win"
  if [ "$count" -gt 1 ]; then
    name="$sess/$win:$widx"
  fi
  if [ "$pidx" != "0" ]; then
    name="$name.$pidx"
  fi
  echo "$name"
}

echo "Restoring AI sessions from $INPUT_FILE"
[ "$DRY_RUN" = true ] && echo "(DRY RUN — no commands will be sent)"
echo ""

total=$(jq length "$INPUT_FILE")
restored=0
failed=0

find_target_pane() {
  local tmux_session="$1" win_idx="$2" win_name="$3" pane_idx="$4"

  # Try exact match first: session:window_index.pane_index
  if tmux list-panes -t "$tmux_session:$win_idx" -F '#{pane_index}' 2>/dev/null | grep -qx "$pane_idx"; then
    echo "$tmux_session:$win_idx.$pane_idx"
    return 0
  fi

  # Fallback: find window by name, then check pane index
  local found_win
  found_win=$(tmux list-windows -t "$tmux_session" -F '#{window_index}|#{window_name}' 2>/dev/null \
    | grep "|${win_name}$" | head -1 | cut -d'|' -f1)

  if [ -n "$found_win" ]; then
    if tmux list-panes -t "$tmux_session:$found_win" -F '#{pane_index}' 2>/dev/null | grep -qx "$pane_idx"; then
      echo "$tmux_session:$found_win.$pane_idx"
      return 0
    fi
  fi

  return 1
}

for i in $(seq 0 $((total - 1))); do
  tmux_session=$(jq -r ".[$i].tmux_session" "$INPUT_FILE")
  win_idx=$(jq -r ".[$i].window_index" "$INPUT_FILE")
  win_name=$(jq -r ".[$i].window_name" "$INPUT_FILE")
  pane_idx=$(jq -r ".[$i].pane_index" "$INPUT_FILE")
  agent_type=$(jq -r ".[$i].agent_type" "$INPUT_FILE")
  session_id=$(jq -r ".[$i].session_id" "$INPUT_FILE")
  cwd=$(jq -r ".[$i].cwd" "$INPUT_FILE")

  label=$(pane_label "$tmux_session" "$win_name" "$pane_idx" "$win_idx")

  # Verify the tmux session exists
  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    echo "  SKIP $label — tmux session does not exist"
    failed=$((failed + 1))
    continue
  fi

  # Find the target pane (with fallback to window name matching)
  target=$(find_target_pane "$tmux_session" "$win_idx" "$win_name" "$pane_idx" || true)
  if [ -z "$target" ]; then
    echo "  SKIP $label — pane not found"
    failed=$((failed + 1))
    continue
  fi

  # Skip if pane already has Claude/Codex running
  target_pid=$(tmux list-panes -t "$target" -F '#{pane_pid}' 2>/dev/null | head -1)
  if [ -n "$target_pid" ]; then
    children=$(pgrep -P "$target_pid" 2>/dev/null || true)
    already_running=false
    for child in $children; do
      child_args=$(ps -p "$child" -o args= 2>/dev/null || true)
      if echo "$child_args" | grep -qw "claude\|codex"; then
        already_running=true
        break
      fi
    done
    if [ "$already_running" = true ]; then
      echo "  SKIP $label — already running"
      failed=$((failed + 1))
      continue
    fi
  fi

  # Build the resume command
  # Note: claude alias already adds --dangerously-skip-permissions and --chrome
  resume_cmd=""
  if [ "$agent_type" = "claude" ]; then
    resume_cmd="cd \"$cwd\" && claude --resume $session_id"
  elif [ "$agent_type" = "codex" ]; then
    resume_cmd="cd \"$cwd\" && codex resume $session_id"
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  $label [$agent_type] $session_id"
    echo "    -> $resume_cmd"
  else
    echo "  OK $label [$agent_type]"
    tmux send-keys -t "$target" "$resume_cmd" Enter
    sleep "$DELAY"
  fi

  restored=$((restored + 1))
done

echo ""
echo "Restored $restored/$total sessions ($failed skipped)."
