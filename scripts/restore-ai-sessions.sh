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

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/tmux-restore-pane.sh"

INPUT_FILE="$HOME/.tmux-ai-sessions.json"
DRY_RUN=false
DELAY="${DELAY:-2}"  # seconds between launching sessions
RESUME_TIMEOUT="${RESUME_TIMEOUT:-20}"  # seconds to verify a resumed process

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

if [ ! -f "$INPUT_FILE" ]; then
  echo "No AI session manifest found at $INPUT_FILE"
  exit 0
fi

pane_label() {
  local sess="$1" win="$2" pidx="$3" widx="$4"
  local count
  count=$(tmux list-windows -t "=$sess" -F '#{window_name}' 2>/dev/null | grep -cx "$win" || true)
  count=${count:-0}
  local name="$sess/$win"
  if [ "$count" -gt 1 ]; then
    name="$sess/$win:$widx"
  fi
  if [ "$pidx" != "0" ]; then
    name="$name.$pidx"
  fi
  echo "$name"
}

codex_rollout_exists() {
  local session_id="$1"
  [ -n "$session_id" ] && [ "$session_id" != "null" ] || return 1
  find "$HOME/.codex/sessions" "$HOME/.codex/archived_sessions" \
    -type f -name "*-$session_id.jsonl" -print -quit 2>/dev/null | grep -q .
}

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

agent_process_in_pane() {
  local target="$1" expected_type="${2:-}" expected_id="${3:-}"
  local pane_pid pid args
  pane_pid=$(tmux list-panes -t "$target" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -n "$pane_pid" ] || return 1

  for pid in $(process_tree "$pane_pid"); do
    [ "$pid" = "$pane_pid" ] && continue
    args=$(ps -p "$pid" -o command= 2>/dev/null || true)
    [ -n "$args" ] || continue

    if [ -n "$expected_type" ]; then
      echo "$args" | grep -Eq "(^|[ /])${expected_type}([[:space:]]|$)" || continue
    else
      echo "$args" | grep -Eq '(^|[ /])(codex|claude)([[:space:]]|$)' || continue
    fi

    if [ -n "$expected_id" ]; then
      echo "$args" | grep -Fq -- "$expected_id" || continue
    fi
    return 0
  done

  return 1
}

wait_for_agent() {
  local target="$1" agent_type="$2" session_id="$3" attempts=$((RESUME_TIMEOUT * 2))
  while [ "$attempts" -gt 0 ]; do
    if agent_process_in_pane "$target" "$agent_type" "$session_id"; then
      return 0
    fi
    sleep 0.5
    attempts=$((attempts - 1))
  done
  return 1
}

echo "Restoring AI sessions from $INPUT_FILE"
[ "$DRY_RUN" = true ] && echo "(DRY RUN — no commands will be sent)"
echo ""

total=$(jq length "$INPUT_FILE")
restored=0
failed=0

if [ "$total" -eq 0 ]; then
  echo "No AI sessions saved."
  echo ""
  echo "Restored 0/0 sessions (0 skipped)."
  exit 0
fi

update_ai_cli() {
  local agent_type="$1"

  if ! jq -e --arg agent_type "$agent_type" 'any(.[]; .agent_type == $agent_type)' "$INPUT_FILE" >/dev/null; then
    return 0
  fi

  if ! command -v "$agent_type" >/dev/null 2>&1; then
    echo "  SKIP $agent_type update — command not found"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  UPDATE $agent_type — $agent_type update"
    return 0
  fi

  echo "  UPDATE $agent_type — running '$agent_type update'"
  if "$agent_type" update; then
    echo "  UPDATE $agent_type — done"
  else
    echo "  WARNING: $agent_type update failed; continuing with restore"
  fi
}

echo "Updating AI CLIs before session restore..."
update_ai_cli claude
update_ai_cli codex
echo ""

for i in $(seq 0 $((total - 1))); do
  tmux_session=$(jq -r ".[$i].tmux_session" "$INPUT_FILE")
  win_idx=$(jq -r ".[$i].window_index" "$INPUT_FILE")
  win_name=$(jq -r ".[$i].window_name" "$INPUT_FILE")
  pane_idx=$(jq -r ".[$i].pane_index" "$INPUT_FILE")
  agent_type=$(jq -r ".[$i].agent_type" "$INPUT_FILE")
  session_id=$(jq -r ".[$i].session_id" "$INPUT_FILE")
  cwd=$(jq -r ".[$i].cwd" "$INPUT_FILE")

  label=$(pane_label "$tmux_session" "$win_name" "$pane_idx" "$win_idx")

  if [ "$agent_type" = "codex" ] && ! codex_rollout_exists "$session_id"; then
    echo "  SKIP $label — saved Codex session not found: $session_id"
    failed=$((failed + 1))
    continue
  fi

  target=$(tmux_restore_find_pane "$tmux_session" "$win_idx" "$win_name" "$pane_idx" || true)
  if [ -z "$target" ] && [ "$DRY_RUN" != true ]; then
    if ! tmux_restore_ensure_pane "$tmux_session" "$win_idx" "$win_name" "$pane_idx" "$cwd"; then
      echo "  SKIP $label — could not create target pane"
      failed=$((failed + 1))
      continue
    fi
    target=$(tmux_restore_find_pane "$tmux_session" "$win_idx" "$win_name" "$pane_idx" || true)
  fi

  if [ -z "$target" ]; then
    echo "  SKIP $label — pane not found"
    failed=$((failed + 1))
    continue
  fi

  if agent_process_in_pane "$target" "$agent_type" "$session_id"; then
    echo "  OK $label [$agent_type] — expected session already running"
    restored=$((restored + 1))
    continue
  fi
  if agent_process_in_pane "$target"; then
    echo "  FAIL $label [$agent_type] — a different AI session is already running"
    failed=$((failed + 1))
    continue
  fi

  # Build the resume command. The pane is the configured tmux default shell,
  # which is zsh in the public tmux config, so the shell remains after resume
  # exits.
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
    pane_command=$(tmux list-panes -t "$target" -F '#{pane_current_command}' 2>/dev/null | head -1)
    case "$pane_command" in
      bash|zsh|sh|fish|login) ;;
      *)
        echo "  FAIL $label [$agent_type] — pane has '$pane_command' running"
        failed=$((failed + 1))
        continue
        ;;
    esac

    tmux copy-mode -t "$target" 2>/dev/null || true
    tmux send-keys -t "$target" -X cancel 2>/dev/null || true
    tmux send-keys -t "$target" C-c C-u
    tmux send-keys -t "$target" "$resume_cmd" Enter
    if wait_for_agent "$target" "$agent_type" "$session_id"; then
      echo "  OK $label [$agent_type]"
    else
      echo "  FAIL $label [$agent_type] — expected session did not start"
      failed=$((failed + 1))
      continue
    fi
    sleep "$DELAY"
  fi

  restored=$((restored + 1))
done

echo ""
echo "Restored $restored/$total sessions ($failed skipped)."
[ "$failed" -eq 0 ]
