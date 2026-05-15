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
restore_status=0
mosh_status=0
ai_status=0
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

ensure_tmux_socket_env() {
  if [ -n "${TMUX:-}" ]; then
    return 0
  fi

  local socket_dir socket_path
  socket_dir="/tmp/tmux-$(id -u)"
  socket_path="$socket_dir/default"
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

echo "═══ Restoring tmux state ═══"
echo ""

if [ -n "${TMUX:-}" ]; then
  current_session=$(tmux display-message -p '#S' 2>/dev/null || true)
  echo "NOTE: running from inside tmux${current_session:+ session '$current_session'}."
  echo "      Existing panes may be preserved by tmux-resurrect; failures will be reported instead of aborting."
  echo ""
else
  ensure_tmux_socket_env
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
  if [ "$ai_status" -ne 0 ]; then
    echo "WARNING: AI restore exited with status $ai_status"
  fi
else
  echo "WARNING: restore-ai-sessions.sh not found at $SCRIPTS_DIR/restore-ai-sessions.sh"
  ai_status=127
fi

echo ""
if [ "$restore_status" -eq 0 ] && [ "$mosh_status" -eq 0 ] && [ "$ai_status" -eq 0 ]; then
  echo "═══ Done. ═══"
else
  echo "═══ Done with warnings. tmux=$restore_status mosh=$mosh_status ai=$ai_status ═══"
  exit 1
fi
