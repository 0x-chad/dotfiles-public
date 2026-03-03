#!/bin/bash
# save-ai-sessions.sh — Capture all Claude/Codex session IDs from tmux panes
# Run before reboot. Sends /status to each AI pane and saves the mapping.
#
# Usage: ~/scripts/save-ai-sessions.sh [wait_seconds]
#   wait_seconds: time to wait after /status for response (default: 4)
#
# Flags:
#   --dry-run     Only detect panes, don't send /status
#   --skip=NAME   Skip tmux session NAME (repeatable)
#   --force       Skip the activity check and proceed anyway

set -euo pipefail

OUTPUT_FILE="$HOME/.tmux-ai-sessions.json"
WAIT_SECS=4
DRY_RUN=false
FORCE=false
SKIP_SESSIONS=()
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
ACTIVITY_WAIT=10  # seconds to wait between activity snapshots

# Parse args
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --skip=*) SKIP_SESSIONS+=("${arg#--skip=}") ;;
    [0-9]*) WAIT_SECS="$arg" ;;
  esac
done

SELF_PANE="${TMUX_PANE:-}"

# ── Helpers ─────────────────────────────────────────────────────────────

should_skip_session() {
  local sess="$1"
  for skip in "${SKIP_SESSIONS[@]+"${SKIP_SESSIONS[@]}"}"; do
    [ "$sess" = "$skip" ] && return 0
  done
  return 1
}

# Human-readable label: "session/window" with index suffix for duplicates
pane_label() {
  local sess="$1" win="$2" pidx="$3" widx="$4"
  local count
  count=$(tmux list-windows -t "$sess" -F '#{window_name}' 2>/dev/null | grep -cx "$win")
  local name="$sess/$win"
  # Disambiguate duplicate window names with index
  if [ "$count" -gt 1 ]; then
    name="$sess/$win:$widx"
  fi
  if [ "$pidx" != "0" ]; then
    name="$name.$pidx"
  fi
  echo "$name"
}

# ── Detect AI panes ────────────────────────────────────────────────────

declare -a PANE_IDS=() PANE_LABELS=() PANE_TYPES=()
declare -a PANE_SESSIONS=() PANE_WINIDX=() PANE_WINNAMES=() PANE_PANEIDX=() PANE_PATHS=()

while IFS='|' read -r sess_name win_idx win_name pane_idx pane_pid pane_path pane_id; do
  [ "$pane_id" = "$SELF_PANE" ] && continue
  should_skip_session "$sess_name" && continue

  agent_type=""
  children=$(pgrep -P "$pane_pid" 2>/dev/null || true)
  for child in $children; do
    child_args=$(ps -p "$child" -o args= 2>/dev/null || true)
    if echo "$child_args" | grep -qw "claude"; then
      agent_type="claude"; break
    elif echo "$child_args" | grep -qw "codex"; then
      agent_type="codex"; break
    fi
  done
  [ -z "$agent_type" ] && continue

  PANE_IDS+=("$pane_id")
  PANE_LABELS+=("$(pane_label "$sess_name" "$win_name" "$pane_idx" "$win_idx")")
  PANE_TYPES+=("$agent_type")
  PANE_SESSIONS+=("$sess_name")
  PANE_WINIDX+=("$win_idx")
  PANE_WINNAMES+=("$win_name")
  PANE_PANEIDX+=("$pane_idx")
  PANE_PATHS+=("$pane_path")

done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_pid}|#{pane_current_path}|#{pane_id}')

total=${#PANE_IDS[@]}
echo "Found $total AI panes."

# ── Activity check ──────────────────────────────────────────────────────
if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ] && [ "$total" -gt 0 ]; then
  echo "Checking for activity (${ACTIVITY_WAIT}s)..."

  SNAP_DIR=$(mktemp -d)
  trap 'rm -rf "$SNAP_DIR"' EXIT

  for pid in "${PANE_IDS[@]}"; do
    tmux capture-pane -t "$pid" -p > "$SNAP_DIR/before_${pid}" 2>/dev/null || true
  done

  sleep "$ACTIVITY_WAIT"

  active_panes=()
  idx=0
  for pid in "${PANE_IDS[@]}"; do
    tmux capture-pane -t "$pid" -p > "$SNAP_DIR/after_${pid}" 2>/dev/null || true
    if ! diff -q "$SNAP_DIR/before_${pid}" "$SNAP_DIR/after_${pid}" >/dev/null 2>&1; then
      active_panes+=("${PANE_LABELS[$idx]}")
    fi
    idx=$((idx + 1))
  done

  if [ ${#active_panes[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Active sessions detected:"
    for p in "${active_panes[@]}"; do
      echo "  - $p"
    done
    echo ""
    echo "Wait for them to finish or use --force to skip this check."
    exit 1
  fi

  echo "All idle. Proceeding."
fi

# ── Send /status to all panes in parallel ───────────────────────────────
echo ""
if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN — would send /status to:"
  idx=0
  for pid in "${PANE_IDS[@]}"; do
    echo "  ${PANE_LABELS[$idx]} [${PANE_TYPES[$idx]}]"
    idx=$((idx + 1))
  done
  echo ""
  echo "Done. $total panes detected."
  exit 0
fi

echo "Sending /status to $total panes..."

# Exit copy/scroll mode if active, clear input, type /status
for pid in "${PANE_IDS[@]}"; do
  # cancel-copy-mode is a no-op if not in copy mode
  tmux copy-mode -t "$pid" 2>/dev/null || true
  tmux send-keys -t "$pid" -X cancel 2>/dev/null || true
  tmux send-keys -t "$pid" C-u
  tmux send-keys -t "$pid" "/status"
done

# Brief pause for autocomplete to resolve, then Enter all at once
sleep 0.1

for pid in "${PANE_IDS[@]}"; do
  tmux send-keys -t "$pid" Enter
done

# Wait once for all panes to render their /status output
sleep "$WAIT_SECS"

# ── Capture and parse all panes ─────────────────────────────────────────
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"; rm -rf "${SNAP_DIR:-}"' EXIT
echo "[]" > "$TMPFILE"

found=0
skipped=0

idx=0
for pid in "${PANE_IDS[@]}"; do
  label="${PANE_LABELS[$idx]}"
  agent_type="${PANE_TYPES[$idx]}"
  sess_name="${PANE_SESSIONS[$idx]}"
  win_idx="${PANE_WINIDX[$idx]}"
  win_name="${PANE_WINNAMES[$idx]}"
  pane_idx="${PANE_PANEIDX[$idx]}"
  pane_path="${PANE_PATHS[$idx]}"

  pane_content=$(tmux capture-pane -t "$pid" -p -S -100)

  # Dismiss the /status panel (Claude=Escape, Codex=q)
  if [ "$agent_type" = "claude" ]; then
    tmux send-keys -t "$pid" Escape
  elif [ "$agent_type" = "codex" ]; then
    tmux send-keys -t "$pid" q
  fi

  session_id=""

  if [ "$agent_type" = "claude" ]; then
    # Claude: "Session ID: <uuid>"
    session_id=$(echo "$pane_content" | grep -i "Session ID" | tail -1 | grep -oE "$UUID_RE" || true)
  elif [ "$agent_type" = "codex" ]; then
    # Codex: "Session:          <uuid>"
    session_id=$(echo "$pane_content" | grep -i "Session:" | tail -1 | grep -oE "$UUID_RE" || true)
  fi

  if [ -z "$session_id" ]; then
    echo "  MISS $label [$agent_type]"
    skipped=$((skipped + 1))
  else
    echo "  OK   $label [$agent_type] $session_id"
    found=$((found + 1))

    entry=$(jq -n \
      --arg tmux_session "$sess_name" \
      --arg window_index "$win_idx" \
      --arg window_name "$win_name" \
      --arg pane_index "$pane_idx" \
      --arg pane_id "$pid" \
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

    contents=$(cat "$TMPFILE")
    echo "$contents" | jq --argjson e "$entry" '. + [$e]' > "$TMPFILE"
  fi

  idx=$((idx + 1))
done

cp "$TMPFILE" "$OUTPUT_FILE"

echo ""
echo "Saved $found/$total sessions ($skipped missed) to $OUTPUT_FILE"
