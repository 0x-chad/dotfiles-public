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

wait_for_pane_command() {
  local target="$1"
  local expected="$2"
  local attempts=100

  while [ "$attempts" -gt 0 ]; do
    if [ "$(tmux -L "$socket_name" list-panes -t "$target" -F '#{pane_current_command}' 2>/dev/null)" = "$expected" ]; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}

mkdir -p "$home_dir/.codex/sessions/2026/09/03" "$home_dir/.omp/agent/sessions/test" "$bin_dir" "$socket_dir"
chmod 700 "$socket_dir"

cat > "$bin_dir/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$AI_UPDATE_TEST_LOG"
[ "${1:-}" = "update" ] || sleep 1
STUB
chmod +x "$bin_dir/claude"

cat > "$bin_dir/codex" <<'STUB'
#!/bin/bash
echo "codex $*" >> "$AI_UPDATE_TEST_LOG"
[ "${1:-}" = "update" ] || sleep 1
STUB
chmod +x "$bin_dir/codex"

cat > "$bin_dir/omp" <<'STUB'
#!/bin/bash
echo "omp $*" >> "$AI_UPDATE_TEST_LOG"
[ "${1:-}" = "update" ] || sleep 1
STUB
chmod +x "$bin_dir/omp"

cat > "$bin_dir/hcom" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "list" ]; then
  echo '[]'
  exit 0
fi
echo "hcom $*" >> "$AI_UPDATE_TEST_LOG"
if [ "${1:-}" = "r" ]; then
  exec omp --resume "$2"
fi
STUB
chmod +x "$bin_dir/hcom"

cat > "$bin_dir/tmux" <<STUB
#!/bin/bash
exec "$real_tmux" -L "$socket_name" "\$@"
STUB
chmod +x "$bin_dir/tmux"

printf -v pane_command 'env HOME=%q PATH=%q AI_UPDATE_TEST_LOG=%q zsh -i' "$home_dir" "$bin_dir:$PATH" "$log_file"
tmux -L "$socket_name" new-session -d -s ai -n claude-pane "$pane_command"
tmux -L "$socket_name" new-window -t "=ai" -n codex-pane "$pane_command"
tmux -L "$socket_name" new-window -t "=ai" -n omp-pane "$pane_command"
tmux -L "$socket_name" set-environment -g PATH "$bin_dir:$PATH"
tmux -L "$socket_name" set-environment -g AI_UPDATE_TEST_LOG "$log_file"

# A restored shell can retain text that was typed but never submitted. The
# restore must clear it before sending the resume command.
tmux -L "$socket_name" send-keys -t '=ai:1.0' 'stale-command'

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
  },
  {
    "tmux_session": "ai",
    "window_index": "2",
    "window_name": "omp-pane",
    "pane_index": "0",
    "agent_type": "omp",
    "session_id": "019f0000-0000-7000-8000-000000000001",
    "cwd": "/tmp"
  }
]
JSON

touch "$home_dir/.codex/sessions/2026/09/03/rollout-test-019e25fb-a490-7760-823e-8846b212f28f.jsonl"
touch "$home_dir/.omp/agent/sessions/test/session_019f0000-0000-7000-8000-000000000001.jsonl"

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
grep -qx "omp update" "$log_file" ||
  fail "omp update did not run"
wait_for_line "claude --resume claude-session" ||
  fail "claude resume did not run"
wait_for_line "codex resume 019e25fb-a490-7760-823e-8846b212f28f" ||
  fail "codex resume did not run"
wait_for_line "hcom r 019f0000-0000-7000-8000-000000000001 --run-here --go" ||
  fail "OMP hcom resume did not run"
if grep -q 'stale-command' "$log_file"; then
  fail "restore appended its command to stale shell input"
fi
wait_for_pane_command '=ai:0.0' zsh ||
  fail "Claude pane did not remain in zsh"
wait_for_pane_command '=ai:1.0' zsh ||
  fail "Codex pane did not remain in zsh"
wait_for_pane_command '=ai:2.0' zsh ||
  fail "OMP pane did not remain in zsh"

claude_update_line=$(grep -nx "claude update" "$log_file" | cut -d: -f1)
codex_update_line=$(grep -nx "codex update" "$log_file" | cut -d: -f1)
claude_resume_line=$(grep -nx "claude --resume claude-session" "$log_file" | cut -d: -f1)
codex_resume_line=$(grep -nx "codex resume 019e25fb-a490-7760-823e-8846b212f28f" "$log_file" | cut -d: -f1)
omp_update_line=$(grep -nx "omp update" "$log_file" | cut -d: -f1)
omp_resume_line=$(grep -nx "hcom r 019f0000-0000-7000-8000-000000000001 --run-here --go" "$log_file" | cut -d: -f1)

[ "$claude_update_line" -lt "$claude_resume_line" ] ||
  fail "claude update did not run before claude resume"
[ "$codex_update_line" -lt "$codex_resume_line" ] ||
  fail "codex update did not run before codex resume"
[ "$omp_update_line" -lt "$omp_resume_line" ] ||
  fail "omp update did not run before OMP resume"

grep -q "Updating AI CLIs before session restore" "$output_file" ||
  fail "update phase was not reported"
grep -q "Restored 3/3 sessions (0 skipped)." "$output_file" ||
  fail "sessions were not restored"

echo "PASS: restore-ai-sessions updates CLIs before resumes"
