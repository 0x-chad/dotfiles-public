#!/bin/bash
# restore-tmux.sh — Restore everything after reboot
# 1. Restores tmux layout via tmux-resurrect
# 2. Waits for shells to initialize
# 3. Resumes AI sessions (Claude/Codex)
#
# Usage: ~/scripts/restore-tmux.sh [--dry-run]

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
AUTOSAVE_UNLOCK="$SCRIPTS_DIR/tmux-autosave-unlock.sh"
restore_status=0
mosh_status=0
ai_status=0
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

tmux_default_socket_path() {
  local socket_dir
  socket_dir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
  if [ -d "$socket_dir" ]; then
    socket_dir="$(cd "$socket_dir" && pwd -P)"
  fi
  printf '%s/default\n' "$socket_dir"
}

process_descendants() {
  local parent="$1" child
  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    process_descendants "$child"
    printf '%s\n' "$child"
  done
}

terminate_orphaned_tmux_server() {
  local server_pid="$1" descendants pid attempts alive

  descendants="$(process_descendants "$server_pid" | awk '!seen[$0]++')"
  echo "Found unreachable tmux server PID $server_pid; terminating it and its orphaned panes."

  for pid in $descendants; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  kill -TERM "$server_pid" 2>/dev/null || true

  attempts=50
  while [ "$attempts" -gt 0 ]; do
    alive=false
    for pid in $descendants $server_pid; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=true
        break
      fi
    done
    [ "$alive" = false ] && return 0
    sleep 0.1
    attempts=$((attempts - 1))
  done

  echo "WARNING: orphaned tmux processes ignored TERM; forcing them to exit."
  for pid in $descendants $server_pid; do
    kill -KILL "$pid" 2>/dev/null || true
  done
}

cleanup_orphaned_tmux_servers() {
  local socket_path reachable_pid candidate

  command -v lsof >/dev/null 2>&1 || return 0
  socket_path="$(tmux_default_socket_path)"
  reachable_pid="$(tmux -S "$socket_path" display-message -p '#{pid}' 2>/dev/null || true)"

  for candidate in $(pgrep -x 'tmux|tmux: server' 2>/dev/null || true); do
    [ "$candidate" = "$reachable_pid" ] && continue
    if lsof -a -p "$candidate" -U -Fn 2>/dev/null |
        awk -v path="n$socket_path" '$0 == path || $0 == path " type=STREAM" { found = 1 } END { exit !found }'; then
      terminate_orphaned_tmux_server "$candidate"
    fi
  done
}

ensure_tmux_socket_env() {
  if [ -n "${TMUX:-}" ]; then
    return 0
  fi

  local socket_dir socket_path
  socket_path="$(tmux_default_socket_path)"
  socket_dir="$(dirname "$socket_path")"
  mkdir -p "$socket_dir"
  chmod 700 "$socket_dir"

  # tmux-resurrect's restore.sh reads $TMUX to discover the socket for
  # `tmux -S ... new-session`; provide the default socket when running outside
  # tmux, such as from ssh or a bootstrap shell.
  export TMUX="$socket_path,0,0"
}

resolve_resurrect_dir() {
  local path
  path=$(tmux show-option -gqv @resurrect-dir 2>/dev/null || true)
  if [ -z "$path" ]; then
    if [ -d "$HOME/.tmux/resurrect" ]; then
      path="$HOME/.tmux/resurrect"
    else
      path="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    fi
  fi
  path="${path/#\~/$HOME}"
  path="${path//\$HOME/$HOME}"
  path="${path//\$HOSTNAME/$(hostname)}"
  echo "$path"
}

repair_resurrect_files() {
  local resurrect_dir="$1"
  local last_file="$resurrect_dir/last"
  local latest_file

  if [ -L "$last_file" ] && [ ! -e "$last_file" ]; then
    latest_file=$(ls -t "$resurrect_dir"/tmux_resurrect_*.txt 2>/dev/null | head -1 || true)
    if [ -n "$latest_file" ]; then
      ln -sfn "$(basename "$latest_file")" "$last_file"
      echo "Fixed broken tmux-resurrect last link -> $(basename "$latest_file")"
    else
      echo "WARNING: tmux-resurrect last link is broken and no snapshots were found"
    fi
  fi

  local pane_contents="$resurrect_dir/pane_contents.tar.gz"
  if [ -f "$pane_contents" ] && ! gzip -t "$pane_contents" >/dev/null 2>&1; then
    local backup="$pane_contents.corrupt-$(date +%Y%m%dT%H%M%S)"
    mv "$pane_contents" "$backup"
    echo "Moved corrupt pane contents archive to $backup"
  fi
}

snapshot_has_session() {
  local resurrect_file="$1"
  local session_name="$2"

  [ -f "$resurrect_file" ] || return 1
  awk -F '\t' -v session_name="$session_name" '
    ($1 == "pane" || $1 == "window") && $2 == session_name {
      found = 1
      exit
    }
    END { exit !found }
  ' "$resurrect_file"
}

process_tree_has_agent() {
  local parent="$1" agent_type="$2" child child_args

  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    child_args="$(ps -p "$child" -o command= 2>/dev/null || true)"
    if printf '%s\n' "$child_args" | grep -Eq "(^|[ /])${agent_type}([[:space:]]|$)"; then
      return 0
    fi
    process_tree_has_agent "$child" "$agent_type" && return 0
  done
  return 1
}

find_manifest_pane() {
  local session="$1" window_index="$2" window_name="$3" pane_index="$4"
  local found_window

  if tmux list-panes -t "=${session}:${window_index}" -F '#{pane_index}' 2>/dev/null |
      grep -qx "$pane_index"; then
    printf '=%s:%s.%s\n' "$session" "$window_index" "$pane_index"
    return 0
  fi

  found_window="$(tmux list-windows -t "=$session" -F '#{window_index}|#{window_name}' 2>/dev/null |
    awk -F '|' -v name="$window_name" '$2 == name { print $1; exit }')"
  if [ -n "$found_window" ] &&
      tmux list-panes -t "=${session}:${found_window}" -F '#{pane_index}' 2>/dev/null |
        grep -qx "$pane_index"; then
    printf '=%s:%s.%s\n' "$session" "$found_window" "$pane_index"
    return 0
  fi

  return 1
}

verify_ai_sessions() {
  local manifest="$HOME/.tmux-ai-sessions.json"
  local session window_index window_name pane_index agent_type target pane_pid
  local total=0 running=0

  [ -f "$manifest" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  while IFS=$'\t' read -r session window_index window_name pane_index agent_type; do
    [ -n "$session" ] || continue
    total=$((total + 1))
    target="$(find_manifest_pane "$session" "$window_index" "$window_name" "$pane_index" || true)"
    if [ -n "$target" ]; then
      pane_pid="$(tmux display-message -pt "$target" '#{pane_pid}' 2>/dev/null || true)"
      if [ -n "$pane_pid" ] && process_tree_has_agent "$pane_pid" "$agent_type"; then
        running=$((running + 1))
        continue
      fi
    fi
    echo "ERROR: AI session $session/$window_name.$pane_index [$agent_type] did not stay running."
  done < <(jq -r '.[] | [.tmux_session, .window_index, .window_name, .pane_index, .agent_type] | @tsv' "$manifest")

  echo "Verified $running/$total AI sessions are running."
  [ "$running" -eq "$total" ]
}

launch_restore_worker() {
  local resurrect_dir resurrect_file
  local base_name candidate suffix status_option worker_command arg status

  resurrect_dir="$(resolve_resurrect_dir)"
  resurrect_file="$resurrect_dir/last"
  base_name="${TMUX_RESTORE_RECOVERY_SESSION:-restore-recovery}"
  case "$base_name" in
    ""|*[!A-Za-z0-9_-]*) base_name="restore-recovery" ;;
  esac
  candidate="$base_name"
  suffix=2

  while tmux has-session -t "=$candidate" 2>/dev/null ||
        snapshot_has_session "$resurrect_file" "$candidate"; do
    candidate="$base_name-$suffix"
    suffix=$((suffix + 1))
  done

  status_option="@tmux-restore-status-$$-$RANDOM"
  printf -v worker_command 'HOME=%q TMUX_RESTORE_WORKER=1 %q' "$HOME" "$0"
  for arg in "$@"; do
    printf -v worker_command '%s %q' "$worker_command" "$arg"
  done
  printf -v worker_command \
    '%s; worker_status=$?; tmux set-option -gq %q "$worker_status"; tmux run-shell -b %q; exit "$worker_status"' \
    "$worker_command" "$status_option" \
    "sleep 1; tmux kill-session -t '=$candidate' >/dev/null 2>&1 || true"

  tmux new-session -d -s "$candidate" "$worker_command"
  echo "Restore is running independently in tmux session '$candidate'."

  while tmux has-session -t "=$candidate" 2>/dev/null; do
    status=$(tmux show-option -gqv "$status_option" 2>/dev/null || true)
    [ -z "$status" ] || break
    sleep 0.1
  done

  status=$(tmux show-option -gqv "$status_option" 2>/dev/null || true)
  tmux set-option -gu "$status_option" 2>/dev/null || true
  if [ -z "$status" ]; then
    echo "ERROR: restore session '$candidate' ended before reporting completion."
    return 1
  fi

  echo "Restore session '$candidate' finished with status $status and will remove itself."
  return "$status"
}

echo "═══ Restoring tmux state ═══"
echo ""

if [ "${TMUX_RESTORE_WORKER:-0}" != "1" ] && [ "$DRY_RUN" != true ] && [ -z "${TMUX:-}" ]; then
  cleanup_orphaned_tmux_servers
fi

if [ -n "${TMUX:-}" ]; then
  current_session=$(tmux display-message -p '#S' 2>/dev/null || true)
  echo "NOTE: running from inside tmux${current_session:+ session '$current_session'}."
  echo "      Existing panes may be preserved by tmux-resurrect; failures will be reported instead of aborting."
  echo ""
else
  ensure_tmux_socket_env
fi

if [ "${TMUX_RESTORE_WORKER:-0}" != "1" ] && [ "$DRY_RUN" != true ]; then
  worker_status=0
  launch_restore_worker "$@" || worker_status=$?
  # The restore worker can replace the tmux server while restoring. Unlock from
  # the parent after it exits so autosave records the final server identity.
  if [ "$worker_status" -eq 0 ] && tmux list-sessions >/dev/null 2>&1 && [ -x "$AUTOSAVE_UNLOCK" ]; then
    "$AUTOSAVE_UNLOCK" >/dev/null 2>&1 || true
  fi
  exit "$worker_status"
fi

# Step 1: Restore tmux layout
echo "── Step 1: tmux layout ──"
if [ "$DRY_RUN" = true ]; then
  echo "(DRY RUN — tmux-resurrect will not be run)"
elif [ -x "$RESURRECT_RESTORE" ]; then
  resurrect_dir="$(resolve_resurrect_dir)"
  if ! repair_resurrect_files "$resurrect_dir"; then
    echo "WARNING: resurrect file repair reported an error; continuing"
  fi

  "$RESURRECT_RESTORE"
  restore_status=$?
  if [ "$restore_status" -eq 0 ]; then
    echo "tmux-resurrect restored. Waiting for shells to init..."
    sleep 3
  else
    echo "WARNING: tmux-resurrect exited with status $restore_status; continuing to AI restore"
  fi
else
  echo "WARNING: tmux-resurrect not found at $RESURRECT_RESTORE"
  echo "Skipping layout restore. Create tmux sessions manually first."
  restore_status=127
fi
echo ""

# Step 2: Restore missing mosh sessions
echo "── Step 2: mosh sessions ──"
if [ -x "$SCRIPTS_DIR/restore-mosh-sessions.sh" ]; then
  "$SCRIPTS_DIR/restore-mosh-sessions.sh" "$@"
  mosh_status=$?
  if [ "$mosh_status" -ne 0 ]; then
    echo "WARNING: mosh restore exited with status $mosh_status"
  fi
else
  echo "WARNING: restore-mosh-sessions.sh not found at $SCRIPTS_DIR/restore-mosh-sessions.sh"
  mosh_status=127
fi
echo ""

# Step 3: Resume AI sessions
echo "── Step 3: AI sessions ──"
if [ -x "$SCRIPTS_DIR/restore-ai-sessions.sh" ]; then
  "$SCRIPTS_DIR/restore-ai-sessions.sh" "$@"
  ai_status=$?
  if [ "$ai_status" -eq 0 ] && [ "$DRY_RUN" != true ] && ! verify_ai_sessions; then
    ai_status=1
  fi
  if [ "$ai_status" -ne 0 ]; then
    echo "WARNING: AI restore exited with status $ai_status"
  fi
else
  echo "WARNING: restore-ai-sessions.sh not found at $SCRIPTS_DIR/restore-ai-sessions.sh"
  ai_status=127
fi

echo ""
if [ "$restore_status" -eq 0 ] && [ "$mosh_status" -eq 0 ] && [ "$ai_status" -eq 0 ] && [ "$DRY_RUN" != true ] && [ -x "$AUTOSAVE_UNLOCK" ]; then
  # Preserve the previous manifest until all saved agents are restored.
  "$AUTOSAVE_UNLOCK" >/dev/null 2>&1 || true
fi

if [ "$restore_status" -eq 0 ] && [ "$mosh_status" -eq 0 ] && [ "$ai_status" -eq 0 ]; then
  echo "═══ Done. ═══"
else
  echo "═══ Done with warnings. tmux=$restore_status mosh=$mosh_status ai=$ai_status ═══"
  exit 1
fi
