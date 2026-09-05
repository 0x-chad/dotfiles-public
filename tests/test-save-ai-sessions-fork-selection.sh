#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WRONG_ID="01a00000-0000-7000-8000-000000000011"
RIGHT_ID="01a00000-0000-7000-8000-000000000012"

fail() {
  echo "FAIL: $*" >&2
  [ -f "${output_file:-}" ] && sed -n '1,160p' "$output_file" >&2
  exit 1
}

test_dir="$(mktemp -d)"
test_home="$test_dir/home"
test_bin="$test_dir/bin"
output_file="$test_dir/output"
mkdir -p "$test_home/.codex/sessions/2026/09/04" "$test_bin"
touch "$test_home/.codex/logs_2.sqlite"

cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT

cat > "$test_bin/tmux" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "list-panes -a") echo 'test|0|fork|0|100|/tmp/project|%1' ;;
  "list-windows -t") echo fork ;;
  *) exit 0 ;;
esac
STUB

cat > "$test_bin/pgrep" <<'STUB'
#!/bin/bash
[ "$1" = "-P" ] && [ "$2" = "100" ] && echo 200
STUB

cat > "$test_bin/ps" <<'STUB'
#!/bin/bash
if [ "$2" = "100" ]; then
  echo zsh
elif [ "$2" = "200" ] && [ "${4:-}" = "lstart=" ]; then
  echo 'Fri Sep  4 12:00:00 2026'
elif [ "$2" = "200" ]; then
  echo 'node /tmp/node_modules/@openai/codex/bin/codex --dangerously-bypass-approvals-and-sandbox fork 01a00000-0000-7000-8000-000000000010'
fi
STUB

cat > "$test_bin/date" <<'STUB'
#!/bin/bash
case "$2" in
  'Fri Sep  4 12:00:00 2026') echo 1788548400 ;;
  '2026-09-04T11:59:00Z') echo 1788548340 ;;
  '2026-09-04T12:00:02Z') echo 1788548402 ;;
  *) exit 1 ;;
esac
STUB

cat > "$test_bin/sqlite3" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$test_bin/tmux" "$test_bin/pgrep" "$test_bin/ps" "$test_bin/date" "$test_bin/sqlite3"

# Create the wrong candidate first. The old implementation returned the first
# same-directory rollout in its broad time window instead of the closest one.
cat > "$test_home/.codex/sessions/2026/09/04/rollout-wrong-$WRONG_ID.jsonl" <<JSON
{"payload":{"id":"$WRONG_ID","cwd":"/tmp/project","timestamp":"2026-09-04T11:59:00Z"}}
JSON
cat > "$test_home/.codex/sessions/2026/09/04/rollout-right-$RIGHT_ID.jsonl" <<JSON
{"payload":{"id":"$RIGHT_ID","cwd":"/tmp/project","timestamp":"2026-09-04T12:00:02Z"}}
JSON

if HOME="$test_home" PATH="$test_bin:/usr/bin:/bin" \
  "$REPO_DIR/scripts/save-ai-sessions.sh" >"$output_file" 2>&1; then
  fail "ambiguous fork candidates were accepted"
fi

rm "$test_home/.codex/sessions/2026/09/04/rollout-wrong-$WRONG_ID.jsonl"
HOME="$test_home" PATH="$test_bin:/usr/bin:/bin" \
  "$REPO_DIR/scripts/save-ai-sessions.sh" >"$output_file" 2>&1 || fail "unique fork save failed"

[ "$(jq -r '.[0].session_id' "$test_home/.tmux-ai-sessions.json")" = "$RIGHT_ID" ] ||
  fail "save did not select the rollout closest to the fork process start"

echo "PASS: fork save rejects ambiguity and accepts a unique candidate with global flags"
