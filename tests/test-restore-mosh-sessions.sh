#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
socket_name="restore-mosh-$$"
home_dir="$test_dir/home"
bin_dir="$test_dir/bin"
zsh_dir="$test_dir/zsh"
manifest="$test_dir/mosh.json"
log_file="$test_dir/log"
output_file="$test_dir/output"
real_tmux="$(command -v tmux)"

cleanup() {
  if [ -f "$output_file" ] && [ ! -f "$log_file" ]; then
    sed -n '1,160p' "$output_file" >&2
    "$real_tmux" -L "$socket_name" list-sessions >&2 2>/dev/null || true
    "$real_tmux" -L "$socket_name" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_pid} #{pane_current_command}' >&2 2>/dev/null || true
    "$real_tmux" -L "$socket_name" capture-pane -p -t '=remote:2.0' >&2 2>/dev/null || true
  fi
  "$real_tmux" -L "$socket_name" kill-server 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$home_dir" "$bin_dir" "$zsh_dir"

cat > "$zsh_dir/.zshenv" <<'ZSHENV'
mosh() {
  printf 'mosh %s\n' "$*" >> "$MOSH_TEST_LOG"
}
ZSHENV

printf '#!/bin/bash\nexec "%s" -L "%s" "$@"\n' "$real_tmux" "$socket_name" > "$bin_dir/tmux"
chmod +x "$bin_dir/tmux"

pane_command="sleep 30"
"$real_tmux" -L "$socket_name" new-session -d -s existing -n shell "$pane_command"
"$real_tmux" -L "$socket_name" set-environment -g PATH "$bin_dir:$PATH"
"$real_tmux" -L "$socket_name" set-environment -g HOME "$home_dir"
"$real_tmux" -L "$socket_name" set-environment -g MOSH_TEST_LOG "$log_file"
"$real_tmux" -L "$socket_name" set-environment -g ZDOTDIR "$zsh_dir"

cat > "$manifest" <<'JSON'
[
  {
    "tmux_session": "remote",
    "window_index": 2,
    "window_name": "main",
    "pane_index": 0,
    "cwd": "/tmp",
    "command": "mosh example -- t remote"
  }
]
JSON

HOME="$home_dir" \
PATH="$bin_dir:$PATH" \
MOSH_TEST_LOG="$log_file" \
  TMUX_MOSH_SESSIONS_FILE="$manifest" \
  "$REPO_DIR/scripts/restore-mosh-sessions.sh" --dry-run >"$output_file" 2>&1

if "$real_tmux" -L "$socket_name" has-session -t '=remote' 2>/dev/null; then
  echo "dry-run created a tmux session" >&2
  exit 1
fi

HOME="$home_dir" \
PATH="$bin_dir:$PATH" \
MOSH_TEST_LOG="$log_file" \
  TMUX_MOSH_SESSIONS_FILE="$manifest" \
  DELAY=0 \
  "$REPO_DIR/scripts/restore-mosh-sessions.sh" >"$output_file" 2>&1

grep -qx 'mosh example -- t remote' "$log_file"
"$real_tmux" -L "$socket_name" has-session -t '=remote'
"$real_tmux" -L "$socket_name" list-windows -t '=remote' -F '#{window_index}|#{window_name}' \
  | grep -qx '2|main'
[ "$($real_tmux -L "$socket_name" list-panes -t '=remote:2' -F '#{pane_current_command}')" = zsh ]

echo "PASS: restore-mosh-sessions recreates a zsh-backed missing session"
