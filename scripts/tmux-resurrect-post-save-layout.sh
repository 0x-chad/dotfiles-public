#!/bin/bash
# tmux-resurrect-post-save-layout.sh — Runs right after tmux-resurrect writes a
# layout file: repairs mosh rows, then drops herdr's view sessions.
#
# A herdr-view-<id> session only links a window that is saved with its own
# session. Restored, it would become a separate copy of that window, and the AI
# restore would resume the same agent in it a second time. herdr-manage makes
# the views again after a restore.

set -euo pipefail

file="${1:-}"
[ -n "$file" ] && [ -f "$file" ] || exit 0

"$(dirname "$0")/repair-tmux-resurrect-mosh.sh" "$file"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
awk -F'\t' '!(($1 == "pane" || $1 == "window" || $1 == "grouped_session") && $2 ~ /^herdr-view-/)' "$file" > "$tmp"
mv "$tmp" "$file"
trap - EXIT
