#!/bin/bash
# save-ai-sessions.sh — Capture Claude/Codex/OMP session IDs from tmux panes.
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

codex_rollout_exists() {
  local session_id="$1"
  [ -n "$session_id" ] && [ "$session_id" != "null" ] || return 1
  # Codex compresses older rollouts to .jsonl.zst and still resumes from them,
  # so a session whose file is compressed exists. Matching only .jsonl reported
  # every compressed session as missing and failed the whole save.
  find "$HOME/.codex/sessions" "$HOME/.codex/archived_sessions" \
    -type f \( -name "*-$session_id.jsonl" -o -name "*-$session_id.jsonl.zst" \) \
    -print -quit 2>/dev/null | grep -q .
}

codex_session_is_unpersisted() {
  local session_id="$1" db="$HOME/.codex/state_5.sqlite"
  [ -f "$db" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$db" "$session_id" <<'PY' >/dev/null 2>&1
import sqlite3
import sys

db, session_id = sys.argv[1], sys.argv[2]
try:  # no -shm while no Codex has the WAL database open; then it's not changing
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.execute("select 1 from threads limit 1")
except sqlite3.OperationalError:
    conn = sqlite3.connect(f"file:{db}?immutable=1", uri=True)
try:
    row = conn.execute(
        "select rollout_path, has_user_event from threads where id = ?",
        (session_id,),
    ).fetchone()
finally:
    conn.close()

# No thread row means Codex has not persisted this runtime-only session. A row
# without either a rollout path or user event is likewise still an empty shell.
if row is None or (not row[0] and not row[1]):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

codex_root_thread() {
  # The conversation a session belongs to: a sub-agent's parent, up to the
  # top. Codex only reopens a sub-agent through its parent, so a pane showing
  # one has to save the parent. Prints the id unchanged when it isn't a sub-agent.
  local session_id="$1" db="$HOME/.codex/state_5.sqlite"
  if [ ! -f "$db" ] || ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$session_id"
    return
  fi
  python3 - "$db" "$session_id" <<'PY' 2>/dev/null || printf '%s\n' "$session_id"
import json
import sqlite3
import sys

db, sid = sys.argv[1], sys.argv[2]
try:  # no -shm while no Codex has the WAL database open; then it's not changing
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.execute("select 1 from threads limit 1")
except sqlite3.OperationalError:
    conn = sqlite3.connect(f"file:{db}?immutable=1", uri=True)
seen = set()
try:
    while sid not in seen:
        seen.add(sid)
        row = conn.execute("select source from threads where id = ?", (sid,)).fetchone()
        try:
            source = json.loads(row[0]) if row and row[0] else {}
        except ValueError:
            source = {}
        if not isinstance(source, dict):
            break
        spawn = (source.get("subagent") or {}).get("thread_spawn") or {}
        parent = spawn.get("parent_thread_id") or source.get("parent_thread_id")
        if not parent:
            break
        sid = parent
finally:
    conn.close()
print(sid)
PY
}

omp_session_exists() {
  local session_id="$1"
  [ -n "$session_id" ] && [ "$session_id" != "null" ] || return 1
  find "$HOME/.omp/agent/sessions" -type f -name "*_${session_id}.jsonl" \
    -print -quit 2>/dev/null | grep -q .
}

omp_session_is_unpersisted() {
  # OMP writes the terminal marker as soon as the agent starts, but only writes
  # the transcript once the session has a real turn. A marker whose third line
  # is "fresh" and whose transcript is absent is a started-but-unused agent:
  # there is nothing to resume, so it is an empty shell, not a save failure.
  # Mirrors codex_session_is_unpersisted.
  local pane_id="$1"
  local pane_tty tty_key marker transcript state
  pane_tty=$(omp_tty "$pane_id" || true)
  [ -n "$pane_tty" ] || return 1
  tty_key="${pane_tty#/dev/}"
  tty_key="${tty_key//\//-}"
  marker="$HOME/.omp/agent/terminal-sessions/$tty_key"
  [ -f "$marker" ] || return 1
  transcript=$(sed -n '2p' "$marker" 2>/dev/null || true)
  [ -n "$transcript" ] && [ -f "$transcript" ] && return 1
  state=$(sed -n '3p' "$marker" 2>/dev/null || true)
  [ "$state" = "fresh" ] || return 1
  return 0
}

omp_tty() {
  # The terminal omp itself runs on. Under muxlight that is muxlight's own
  # pty, not the pane's, and a pane terminal's old marker may be stale.
  local pane_id="$1" pane_pid pid tty
  pane_pid=$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null || true)
  for pid in $(process_tree "$pane_pid"); do
    ps_args "$pid" | grep -Eq '(^|[ /])omp([[:space:]]|$)' || continue
    ps_args "$pid" | grep -q 'muxlight' && continue
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$tty" in ""|"?") ;; *) printf '/dev/%s\n' "$tty"; return 0 ;; esac
  done
  tmux display-message -p -t "$pane_id" '#{pane_tty}' 2>/dev/null
}

extract_omp_session_id() {
  local pane_id="$1"
  local pane_tty tty_key marker transcript sid
  # OMP records the active transcript by terminal, so session discovery does
  # not require chat probing or an external agent registry.
  pane_tty=$(omp_tty "$pane_id" || true)
  [ -n "$pane_tty" ] || return 1
  tty_key="${pane_tty#/dev/}"
  tty_key="${tty_key//\//-}"
  marker="$HOME/.omp/agent/terminal-sessions/$tty_key"
  [ -f "$marker" ] || return 1
  transcript=$(sed -n '2p' "$marker" 2>/dev/null || true)
  [ -f "$transcript" ] || return 1
  sid=$(basename "$transcript" | grep -oE "$UUID_RE" | tail -1 || true)
  [ -n "$sid" ] || return 1
  printf '%s\n' "$sid"
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

  echo "$args" | grep -Eq '(^|[ /])codex([[:space:]]|$)' || return 1

  sid=$(echo "$args" | grep -oE "(^|[[:space:]])resume[[:space:]]+$UUID_RE" \
    | tail -1 | grep -oE "$UUID_RE" || true)
  if [ -n "$sid" ]; then
    echo "$sid"
    return 0
  fi

  return 1
}

extract_codex_session_id_from_fd() {
  # A running codex process keeps its rollout .jsonl open, so /proc/<pid>/fd
  # names the session outright. This is exact -- unlike cwd+timestamp matching,
  # it cannot be ambiguous -- so it is tried before any heuristic.
  local pane_pid="$1" pid target sid
  for pid in $(process_tree "$pane_pid"); do
    for target in /proc/"$pid"/fd/*; do
      [ -e "$target" ] || continue
      sid=$(readlink "$target" 2>/dev/null | grep -oE "rollout-[0-9T:-]+-$UUID_RE\.jsonl" | grep -oE "$UUID_RE" | head -1)
      if [ -n "$sid" ]; then
        printf '%s\n' "$sid"
        return 0
      fi
    done
  done
  return 1
}

extract_codex_session_id() {
  # The id a codex process was started with: "resume <id>" on its command
  # line, or a rollout file it holds open. Exact, but only the launch id; the
  # screen match in codex-session-match follows /new, /resume and sub-agents.
  local pane_pid="$1" pid args sid

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue
    sid=$(extract_codex_session_id_from_args "$args" || true)
    if [ -n "$sid" ]; then
      echo "$sid"
      return 0
    fi
  done

  extract_codex_session_id_from_fd "$pane_pid"
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

declare -a PANE_IDS=() PANE_LABELS=() PANE_TYPES=() PANE_SESSION_IDS=() PANE_ERRORS=()
declare -a PANE_SESSIONS=() PANE_WINIDX=() PANE_WINNAMES=() PANE_PANEIDX=() PANE_PATHS=()
declare -a EMPTY_CODEX_PANES=()
declare -a EMPTY_OMP_PANES=()

# Which Codex session each pane shows, matched from the replies on its screen.
CODEX_MATCHES=$(mktemp)
"$(dirname "$0")/codex-session-match" $(tmux list-panes -a -F '#{pane_id}') > "$CODEX_MATCHES" 2>/dev/null || true

while IFS='|' read -r sess_name win_idx win_name pane_idx pane_pid pane_path pane_id; do
  # herdr's view sessions only link windows saved under their own session.
  case "$sess_name" in herdr-view-*) continue ;; esac
  [ "$pane_id" = "$SELF_PANE" ] && continue
  should_skip_session "$sess_name" && continue

  agent_type=""
  session_id=""
  session_error=""
  via_subagent=0

  for pid in $(process_tree "$pane_pid"); do
    args=$(ps_args "$pid")
    [ -z "$args" ] && continue
    if echo "$args" | grep -Eq '(^|[ /])claude([[:space:]]|$)'; then
      agent_type="claude"
      break
    elif echo "$args" | grep -Eq '(^|[ /])codex([[:space:]]|$)'; then
      agent_type="codex"
      break
    elif echo "$args" | grep -Eq '(^|[ /])omp([[:space:]]|$)'; then
      agent_type="omp"
      break
    fi
  done
  [ -z "$agent_type" ] && continue

  if [ "$agent_type" = "claude" ]; then
    session_id=$(extract_claude_session_id "$pane_pid" || true)
  elif [ "$agent_type" = "codex" ]; then
    match=$(awk -F'\t' -v p="$pane_id" '$1 == p {print $2 "\t" $3; exit}' "$CODEX_MATCHES")
    match_status=${match%%$'\t'*}
    case "$match_status" in
      ok) session_id=${match#*$'\t'} ;;
      subagent) session_id=${match#*$'\t'}; via_subagent=1 ;;
      *)
        # Nothing on screen to match: fall back to the id it was started with.
        session_id=$(extract_codex_session_id "$pane_pid" || true)
        if [ -n "$session_id" ]; then
          root_id=$(codex_root_thread "$session_id")
          if [ -n "$root_id" ] && [ "$root_id" != "$session_id" ]; then
            session_id="$root_id"
            via_subagent=1
          fi
        elif [ "$match_status" = "empty" ]; then
          EMPTY_CODEX_PANES+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
          continue
        else
          session_error="no saved session matches the replies on screen"
        fi
        ;;
    esac
    if [ -n "$session_id" ] && ! codex_rollout_exists "$session_id"; then
      if codex_session_is_unpersisted "$session_id"; then
        EMPTY_CODEX_PANES+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
        continue
      else
        session_error="session ID $session_id has no saved rollout"
        session_id=""
      fi
    fi
  elif [ "$agent_type" = "omp" ]; then
    session_id=$(extract_omp_session_id "$pane_id" || true)
    if [ -z "$session_id" ] || ! omp_session_exists "$session_id"; then
      if omp_session_is_unpersisted "$pane_id"; then
        EMPTY_OMP_PANES+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
        continue
      elif [ -n "$session_id" ]; then
        session_error="session ID $session_id has no saved OMP transcript"
        session_id=""
      fi
    fi
  fi

  PANE_IDS+=("$pane_id")
  PANE_LABELS+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
  PANE_TYPES+=("$agent_type")
  PANE_SESSION_IDS+=("$session_id")
  PANE_ERRORS+=("$session_error")
  PANE_SESSIONS+=("$sess_name")
  PANE_WINIDX+=("$win_idx")
  PANE_WINNAMES+=("$win_name")
  PANE_PANEIDX+=("$pane_idx")
  PANE_PATHS+=("$pane_path")
  PANE_VIA_SUBAGENT+=("$via_subagent")
done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_pid}|#{pane_current_path}|#{pane_id}')

total=${#PANE_IDS[@]}
echo "Found $total AI panes."
for label in "${EMPTY_CODEX_PANES[@]+"${EMPTY_CODEX_PANES[@]}"}"; do
  echo "  EMPTY $label [codex] — no persisted user turn; ignored"
done
for label in "${EMPTY_OMP_PANES[@]+"${EMPTY_OMP_PANES[@]}"}"; do
  echo "  EMPTY $label [omp] — no persisted transcript; ignored"
done

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMPFILE.next" "$CODEX_MATCHES"; rm -rf "${SNAP_DIR:-}"' EXIT
echo "[]" > "$TMPFILE"

found=0
shared=0
skipped=0
unresolved=()

# Panes on their own session first, then panes showing a sub-agent. A session
# is saved once: a sub-agent pane whose parent another window already holds is
# skipped, so a restore never runs the same conversation twice.
saved_ids=" "
for pass in 0 1; do
  for idx in "${!PANE_IDS[@]}"; do
    [ "${PANE_VIA_SUBAGENT[$idx]}" = "$pass" ] || continue
    session_id="${PANE_SESSION_IDS[$idx]}"
    if [ -n "$session_id" ]; then
      case "$saved_ids" in
        *" $session_id "*)
          echo "  SAME ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] — shows a sub-agent of $session_id, saved for another window"
          shared=$((shared + 1))
          continue ;;
      esac
      saved_ids+="$session_id "
      echo "  OK   ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] $session_id"
      append_entry "$TMPFILE" \
        "${PANE_SESSIONS[$idx]}" "${PANE_WINIDX[$idx]}" "${PANE_WINNAMES[$idx]}" "${PANE_PANEIDX[$idx]}" \
        "${PANE_IDS[$idx]}" "${PANE_TYPES[$idx]}" "$session_id" "${PANE_PATHS[$idx]}"
      found=$((found + 1))
    else
      unresolved+=("$idx")
    fi
  done
done

if [ ${#unresolved[@]} -gt 0 ] && [ "$PROBE_STATUS" != true ]; then
  for idx in "${unresolved[@]}"; do
    if [ -n "${PANE_ERRORS[$idx]}" ]; then
      echo "  MISS ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] — ${PANE_ERRORS[$idx]}"
    else
      echo "  MISS ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}] — use --probe-status to query the chat"
    fi
    skipped=$((skipped + 1))
  done
fi

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "DRY RUN — identified $found/$total sessions ($skipped missed)."
  if [ $((found + shared)) -ne "$total" ]; then
    exit 1
  fi
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
      if [ -n "$session_id" ] && ! codex_rollout_exists "$session_id"; then
        PANE_ERRORS[$idx]="session ID $session_id has no saved rollout"
        session_id=""
      fi
    elif [ "$agent_type" = "omp" ]; then
      session_id=$(extract_omp_session_id "${PANE_IDS[$idx]}" || true)
    fi

    if [ -z "$session_id" ]; then
      if [ -n "${PANE_ERRORS[$idx]}" ]; then
        echo "  MISS ${PANE_LABELS[$idx]} [$agent_type] — ${PANE_ERRORS[$idx]}"
      else
        echo "  MISS ${PANE_LABELS[$idx]} [$agent_type]"
      fi
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

# A pane with no session id is only a failure when extraction actually failed
# (PANE_ERRORS is set). An agent that is running but has no conversation yet
# has nothing to resume, which is normal: a freshly started agent, or one
# still booting. Those must not block saving everyone else's sessions.
failed=0
for idx in "${unresolved[@]+"${unresolved[@]}"}"; do
  [ -n "${PANE_ERRORS[$idx]}" ] && failed=$((failed + 1))
done

if [ "$failed" -gt 0 ]; then
  echo ""
  echo "ERROR: $failed/$total AI sessions failed to resolve (found $found)."
  if [ -s "$OUTPUT_FILE" ]; then
    echo "Preserving existing manifest at $OUTPUT_FILE"
  else
    echo "No manifest written."
  fi
  exit 1
fi

# Identifying nothing at all is not an error above: every pane may legitimately
# be an agent with no conversation yet. But writing that empty result over a
# manifest that still has sessions in it loses the only record of what to
# restore. That window is reachable -- right after a restore, while agents are
# still booting, every pane is "no session yet" -- and autosave runs on a timer,
# so keep the older manifest and let the next run replace it.
if [ "$found" -eq 0 ] && [ "$total" -gt 0 ] && [ -s "$OUTPUT_FILE" ] \
  && [ "$(jq length "$OUTPUT_FILE" 2>/dev/null || echo 0)" -gt 0 ]; then
  echo ""
  echo "WARNING: identified 0/$total sessions; preserving existing non-empty manifest at $OUTPUT_FILE"
  exit 1
fi

cp "$TMPFILE" "$OUTPUT_FILE"

echo ""
echo "Saved $found/$total sessions ($skipped with no session yet) to $OUTPUT_FILE"
