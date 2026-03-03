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

echo "═══ Restoring tmux state ═══"
echo ""

# Step 1: Restore tmux layout
echo "── Step 1: tmux layout ──"
if [ -x "$RESURRECT_RESTORE" ]; then
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
