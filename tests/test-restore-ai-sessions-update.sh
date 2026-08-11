#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  if [ -n "${output_file:-}" ] && [ -f "$output_file" ]; then
    echo "--- restore output ---" >&2
    sed -n '1,200p' "$output_file" >&2
  fi
  if [ -n "${log_file:-}" ] && [ -f "$log_file" ]; then
    echo "--- command log ---" >&2
    sed -n '1,200p' "$log_file" >&2
  fi
  exit 1
}

test_dir="$(mktemp -d)"
socket_name="restore-ai-update-$$"
socket_dir="$test_dir/tmux"
socket_path="$socket_dir/default"
home_dir="$test_dir/home"
bin_dir="$test_dir/bin"
log_file="$test_dir/log"
output_file="$test_dir/output"
real_tmux="$(command -v tmux)"
pane_command=""

cleanup() {
  tmux -L "$socket_name" kill-server 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

wait_for_line() {
  local line="$1"
  local attempts=100

  while [ "$attempts" -gt 0 ]; do
    if [ -f "$log_file" ] && grep -qx "$line" "$log_file"; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}

mkdir -p "$home_dir" "$bin_dir" "$socket_dir"
chmod 700 "$socket_dir"

cat > "$bin_dir/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$AI_UPDATE_TEST_LOG"
STUB
chmod +x "$bin_dir/claude"

cat > "$bin_dir/codex" <<'STUB'
#!/bin/bash
echo "codex $*" >> "$AI_UPDATE_TEST_LOG"
STUB
chmod +x "$bin_dir/codex"

cat > "$bin_dir/tmux" <<STUB
#!/bin/bash
exec "$real_tmux" -L "$socket_name" "\$@"
STUB
chmod +x "$bin_dir/tmux"

printf -v pane_command 'env PATH=%q AI_UPDATE_TEST_LOG=%q bash --noprofile --norc' "$bin_dir:$PATH" "$log_file"
tmux -L "$socket_name" new-session -d -s ai -n claude-pane "$pane_command"
tmux -L "$socket_name" new-window -t "=ai" -n codex-pane "$pane_command"
tmux -L "$socket_name" set-environment -g PATH "$bin_dir:$PATH"
tmux -L "$socket_name" set-environment -g AI_UPDATE_TEST_LOG "$log_file"

cat > "$home_dir/.tmux-ai-sessions.json" <<'JSON'
[
  {
    "tmux_session": "ai",
    "window_index": "0",
    "window_name": "claude-pane",
    "pane_index": "0",
    "agent_type": "claude",
    "session_id": "claude-session",
    "cwd": "/tmp"
  },
  {
    "tmux_session": "ai",
    "window_index": "1",
    "window_name": "codex-pane",
    "pane_index": "0",
    "agent_type": "codex",
    "session_id": "019e25fb-a490-7760-823e-8846b212f28f",
    "cwd": "/tmp"
  }
]
JSON

HOME="$home_dir" \
PATH="$bin_dir:$PATH" \
TMUX="$socket_path,0,0" \
AI_UPDATE_TEST_LOG="$log_file" \
DELAY=0 \
  "$REPO_DIR/scripts/restore-ai-sessions.sh" >"$output_file" 2>&1

grep -qx "claude update" "$log_file" ||
  fail "claude update did not run"
grep -qx "codex update" "$log_file" ||
  fail "codex update did not run"
wait_for_line "claude --resume claude-session" ||
  fail "claude resume did not run"
wait_for_line "codex resume 019e25fb-a490-7760-823e-8846b212f28f" ||
  fail "codex resume did not run"

claude_update_line=$(grep -nx "claude update" "$log_file" | cut -d: -f1)
codex_update_line=$(grep -nx "codex update" "$log_file" | cut -d: -f1)
claude_resume_line=$(grep -nx "claude --resume claude-session" "$log_file" | cut -d: -f1)
codex_resume_line=$(grep -nx "codex resume 019e25fb-a490-7760-823e-8846b212f28f" "$log_file" | cut -d: -f1)

[ "$claude_update_line" -lt "$claude_resume_line" ] ||
  fail "claude update did not run before claude resume"
[ "$codex_update_line" -lt "$codex_resume_line" ] ||
  fail "codex update did not run before codex resume"

grep -q "Updating AI CLIs before session restore" "$output_file" ||
  fail "update phase was not reported"
grep -q "Restored 2/2 sessions (0 skipped)." "$output_file" ||
  fail "sessions were not restored"

echo "PASS: restore-ai-sessions updates CLIs before resumes"
