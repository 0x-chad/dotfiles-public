#!/bin/bash
# save-ai-sessions.sh — Capture Claude/Codex session IDs from tmux panes.
#
# Default mode is non-invasive: it reads process args and local state databases
# without sending anything into the chat. Use --probe-status to fall back to the
# older /status probing behavior for panes that cannot be identified.
#
# Usage: ~/scripts/save-ai-sessions.sh [wait_seconds]
#   wait_seconds: time to wait after /status for response with --probe-status
#
# Flags:
#   --dry-run        Detect panes only; do not write the manifest or send input
#   --probe-status   Send /status only for panes not identified non-invasively
#   --skip=NAME      Skip tmux session NAME (repeatable)
#   --force          Skip the activity check before --probe-status

set -euo pipefail

OUTPUT_FILE="$HOME/.tmux-ai-sessions.json"
WAIT_SECS=4
DRY_RUN=false
PROBE_STATUS=false
FORCE=false
SKIP_SESSIONS=()
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
ACTIVITY_WAIT=10
SELF_PANE="${TMUX_PANE:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --probe-status) PROBE_STATUS=true ;;
    --force) FORCE=true ;;
    --skip=*) SKIP_SESSIONS+=("${arg#--skip=}") ;;
    [0-9]*) WAIT_SECS="$arg" ;;
  esac
done

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required." >&2
    exit 1
  fi
}

should_skip_session() {
  local sess="$1" skip
  for skip in "${SKIP_SESSIONS[@]+"${SKIP_SESSIONS[@]}"}"; do
    [ "$sess" = "$skip" ] && return 0
  done
  return 1
}

pane_label() {
  local sess="$1" win="$2" pidx="$3" widx="$4"
  local count name
  count=$(tmux list-windows -t "$sess" -F '#{window_name}' 2>/dev/null | grep -cx "$win" || true)
  count=${count:-0}
  name="$sess/$win"
  if [ "$count" -gt 1 ]; then
    name="$sess/$win:$widx"
  fi
  if [ "$pidx" != "0" ]; then
    name="$name.$pidx"
  fi
  echo "$name"
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

ps_args() {
  ps -p "$1" -o command= 2>/dev/null || true
}

extract_claude_session_id() {
  local pane_pid="$1" pid args sid session_file

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue

    sid=$(echo "$args" | grep -oE -- "((--(resume|session-id)[ =])|(-r[[:space:]]+))$UUID_RE" | tail -1 | grep -oE "$UUID_RE" || true)
    if [ -n "$sid" ]; then
      echo "$sid"
      return 0
    fi

    session_file="$HOME/.claude/sessions/$pid.json"
    if [ -f "$session_file" ]; then
      sid=$(jq -r '.sessionId // .session_id // .id // empty' "$session_file" 2>/dev/null | grep -oE "$UUID_RE" | head -1 || true)
      if [ -n "$sid" ]; then
        echo "$sid"
        return 0
      fi
    fi
  done

  return 1
}

extract_codex_session_id_from_args() {
  local args="$1" sid

  sid=$(echo "$args" | grep -oE "(^|[[:space:]])codex[[:space:]]+resume[[:space:]]+$UUID_RE" \
    | tail -1 | grep -oE "$UUID_RE" || true)
  if [ -n "$sid" ]; then
    echo "$sid"
    return 0
  fi

  return 1
}

query_codex_log_db() {
  local db="$1" pid="$2"
  local query="select thread_id from logs where process_uuid like 'pid:$pid:%' and thread_id is not null order by ts desc, ts_nanos desc, id desc limit 1;"

  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$db" "$query" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$db" "$pid" <<'PY' 2>/dev/null
import sqlite3
import sys

db, pid = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db)
try:
    row = conn.execute(
        """
        select thread_id
        from logs
        where process_uuid like ?
          and thread_id is not null
        order by ts desc, ts_nanos desc, id desc
        limit 1
        """,
        (f"pid:{pid}:%",),
    ).fetchone()
    if row and row[0]:
        print(row[0])
finally:
    conn.close()
PY
  fi
}

extract_codex_session_id() {
  local pane_pid="$1" pid args sid db

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue

    sid=$(extract_codex_session_id_from_args "$args" || true)
    if [ -n "$sid" ]; then
      echo "$sid"
      return 0
    fi
  done

  db="$HOME/.codex/logs_2.sqlite"
  [ -f "$db" ] || return 1

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue
    echo "$args" | grep -Eq '(^|[ /])codex([[:space:]]|$)' || continue
    echo "$args" | grep -q 'node_modules/@openai/codex' || continue

    sid=$(query_codex_log_db "$db" "$pid" | grep -oE "$UUID_RE" | head -1 || true)
    if [ -n "$sid" ]; then
      echo "$sid"
      return 0
    fi
  done

  return 1
}

append_entry() {
  local tmpfile="$1" sess_name="$2" win_idx="$3" win_name="$4" pane_idx="$5"
  local pane_id="$6" agent_type="$7" session_id="$8" pane_path="$9"
  local entry

  entry=$(jq -n \
    --arg tmux_session "$sess_name" \
    --arg window_index "$win_idx" \
    --arg window_name "$win_name" \
    --arg pane_index "$pane_idx" \
    --arg pane_id "$pane_id" \
    --arg agent_type "$agent_type" \
    --arg session_id "$session_id" \
    --arg cwd "$pane_path" \
    '{
      tmux_session: $tmux_session,
      window_index: ($window_index | tonumber),
      window_name: $window_name,
      pane_index: ($pane_index | tonumber),
      pane_id: $pane_id,
      agent_type: $agent_type,
      session_id: $session_id,
      cwd: $cwd
    }')

  jq --argjson e "$entry" '. + [$e]' "$tmpfile" > "$tmpfile.next"
  mv "$tmpfile.next" "$tmpfile"
}

require_jq

declare -a PANE_IDS=() PANE_LABELS=() PANE_TYPES=() PANE_SESSION_IDS=()
declare -a PANE_SESSIONS=() PANE_WINIDX=() PANE_WINNAMES=() PANE_PANEIDX=() PANE_PATHS=()

while IFS='|' read -r sess_name win_idx win_name pane_idx pane_pid pane_path pane_id; do
  [ "$pane_id" = "$SELF_PANE" ] && continue
  should_skip_session "$sess_name" && continue

  agent_type=""
  session_id=""

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue
    if echo "$args" | grep -Eq '(^|[ /])claude([[:space:]]|$)'; then
      agent_type="claude"
      break
    elif echo "$args" | grep -Eq '(^|[ /])codex([[:space:]]|$)'; then
      agent_type="codex"
      break
    fi
  done
  [ -z "$agent_type" ] && continue

  if [ "$agent_type" = "claude" ]; then
    session_id=$(extract_claude_session_id "$pane_pid" || true)
  elif [ "$agent_type" = "codex" ]; then
    session_id=$(extract_codex_session_id "$pane_pid" || true)
  fi

  PANE_IDS+=("$pane_id")
  PANE_LABELS+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
  PANE_TYPES+=("$agent_type")
  PANE_SESSION_IDS+=("$session_id")
  PANE_SESSIONS+=("$sess_name")
  PANE_WINIDX+=("$win_idx")
  PANE_WINNAMES+=("$win_name")
  PANE_PANEIDX+=("$pane_idx")
  PANE_PATHS+=("$pane_path")
done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_pid}|#{pane_current_path}|#{pane_id}')

total=${#PANE_IDS[@]}
echo "Found $total AI panes."

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMPFILE.next"; rm -rf "${SNAP_DIR:-}"' EXIT
echo "[]" > "$TMPFILE"

found=0
skipped=0
unresolved=()

for idx in "${!PANE_IDS[@]}"; do
  session_id="${PANE_SESSION_IDS[$idx]}"
  if [ -n "$session_id" ]; then
    echo "  OK   ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] $session_id"
    append_entry "$TMPFILE" \
      "${PANE_SESSIONS[$idx]}" "${PANE_WINIDX[$idx]}" "${PANE_WINNAMES[$idx]}" "${PANE_PANEIDX[$idx]}" \
      "${PANE_IDS[$idx]}" "${PANE_TYPES[$idx]}" "$session_id" "${PANE_PATHS[$idx]}"
    found=$((found + 1))
  else
    unresolved+=("$idx")
  fi
done

if [ ${#unresolved[@]} -gt 0 ] && [ "$PROBE_STATUS" != true ]; then
  for idx in "${unresolved[@]}"; do
    echo "  MISS ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] — use --probe-status to query the chat"
    skipped=$((skipped + 1))
  done
fi

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "DRY RUN — identified $found/$total sessions ($skipped missed)."
  exit 0
fi

if [ ${#unresolved[@]} -gt 0 ] && [ "$PROBE_STATUS" = true ]; then
  if [ "$FORCE" != true ]; then
    echo ""
    echo "Checking unresolved panes for activity before /status (${ACTIVITY_WAIT}s)..."
    SNAP_DIR=$(mktemp -d)
    for idx in "${unresolved[@]}"; do
      tmux capture-pane -t "${PANE_IDS[$idx]}" -p > "$SNAP_DIR/before_${PANE_IDS[$idx]}" 2>/dev/null || true
    done
    sleep "$ACTIVITY_WAIT"
    active_panes=()
    for idx in "${unresolved[@]}"; do
      tmux capture-pane -t "${PANE_IDS[$idx]}" -p > "$SNAP_DIR/after_${PANE_IDS[$idx]}" 2>/dev/null || true
      if ! diff -q "$SNAP_DIR/before_${PANE_IDS[$idx]}" "$SNAP_DIR/after_${PANE_IDS[$idx]}" >/dev/null 2>&1; then
        active_panes+=("${PANE_LABELS[$idx]}")
      fi
    done
    if [ ${#active_panes[@]} -gt 0 ]; then
      echo ""
      echo "ERROR: Active unresolved sessions detected:"
      for p in "${active_panes[@]}"; do
        echo "  - $p"
      done
      echo ""
      echo "Wait for them to finish or use --force to skip this check."
      exit 1
    fi
  fi

  echo ""
  echo "Sending /status to ${#unresolved[@]} unresolved pane(s)..."
  for idx in "${unresolved[@]}"; do
    tmux copy-mode -t "${PANE_IDS[$idx]}" 2>/dev/null || true
    tmux send-keys -t "${PANE_IDS[$idx]}" -X cancel 2>/dev/null || true
    tmux send-keys -t "${PANE_IDS[$idx]}" C-u
    tmux send-keys -t "${PANE_IDS[$idx]}" "/status"
  done

  sleep 0.1
  for idx in "${unresolved[@]}"; do
    tmux send-keys -t "${PANE_IDS[$idx]}" Enter
  done

  sleep "$WAIT_SECS"

  for idx in "${unresolved[@]}"; do
    pane_content=$(tmux capture-pane -t "${PANE_IDS[$idx]}" -p -S -100)
    agent_type="${PANE_TYPES[$idx]}"
    session_id=""

    if [ "$agent_type" = "claude" ]; then
      session_id=$(echo "$pane_content" | grep -i "Session ID" | tail -1 | grep -oE "$UUID_RE" || true)
      tmux send-keys -t "${PANE_IDS[$idx]}" Escape
    elif [ "$agent_type" = "codex" ]; then
      session_id=$(echo "$pane_content" | grep -i "Session:" | tail -1 | grep -oE "$UUID_RE" || true)
      tmux send-keys -t "${PANE_IDS[$idx]}" q
    fi

    if [ -z "$session_id" ]; then
      echo "  MISS ${PANE_LABELS[$idx]} [$agent_type]"
      skipped=$((skipped + 1))
    else
      echo "  OK   ${PANE_LABELS[$idx]} [$agent_type] $session_id"
      append_entry "$TMPFILE" \
        "${PANE_SESSIONS[$idx]}" "${PANE_WINIDX[$idx]}" "${PANE_WINNAMES[$idx]}" "${PANE_PANEIDX[$idx]}" \
        "${PANE_IDS[$idx]}" "$agent_type" "$session_id" "${PANE_PATHS[$idx]}"
      found=$((found + 1))
    fi
  done
fi

cp "$TMPFILE" "$OUTPUT_FILE"

echo ""
echo "Saved $found/$total sessions ($skipped missed) to $OUTPUT_FILE"
