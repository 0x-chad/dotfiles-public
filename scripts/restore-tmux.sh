#!/bin/bash
# restore-tmux.sh — Restore everything after reboot
# 1. Restores tmux layout via tmux-resurrect
# 2. Waits for shells to initialize
# 3. Resumes AI sessions (Claude/Codex)
#
# Usage: ~/scripts/restore-tmux.sh [--dry-run]

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

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

# Step 1: Restore tmux layout
echo "── Step 1: tmux layout ──"
if [ -x "$RESURRECT_RESTORE" ]; then
  repair_resurrect_files "$(resolve_resurrect_dir)"
  "$RESURRECT_RESTORE"
  echo "tmux-resurrect restored. Waiting for shells to init..."
  sleep 3
else
  echo "WARNING: tmux-resurrect not found at $RESURRECT_RESTORE"
  echo "Skipping layout restore. Create tmux sessions manually first."
fi
echo ""

# Step 2: Resume AI sessions
echo "── Step 2: AI sessions ──"
"$SCRIPTS_DIR/restore-ai-sessions.sh" "$@"

echo ""
echo "═══ Done. ═══"
