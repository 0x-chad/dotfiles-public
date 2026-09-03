#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ORPHAN_ID="01a00000-0000-7000-8000-000000000001"
VALID_ID="01a00000-0000-7000-8000-000000000002"
OLD_ID="01a00000-0000-7000-8000-000000000003"

fail() {
  echo "FAIL: $*" >&2
  [ -f "${output_file:-}" ] && sed -n '1,160p' "$output_file" >&2
  exit 1
}

test_dir="$(mktemp -d)"
test_home="$test_dir/home"
test_bin="$test_dir/bin"
output_file="$test_dir/output"
sqlite_output="$test_dir/sqlite-output"
mkdir -p "$test_home/.codex/sessions/2026/09/03" "$test_bin"
touch "$test_home/.codex/logs_2.sqlite"

cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT

cat > "$test_bin/tmux" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "list-panes -a")
    echo 'test|0|main|0|100|/tmp/project|%1'
    ;;
  "list-windows -t")
    echo main
    ;;
  *)
    exit 0
    ;;
esac
STUB

cat > "$test_bin/pgrep" <<'STUB'
#!/bin/bash
if [ "$1" = "-P" ] && [ "$2" = "100" ]; then
  echo 200
fi
STUB

cat > "$test_bin/ps" <<'STUB'
#!/bin/bash
case "$2" in
  100) echo zsh ;;
  200) echo 'node /tmp/node_modules/@openai/codex/bin/codex' ;;
esac
STUB

cat > "$test_bin/sqlite3" <<'STUB'
#!/bin/bash
cat "$SAVE_AI_SQLITE_OUTPUT"
STUB
chmod +x "$test_bin/tmux" "$test_bin/pgrep" "$test_bin/ps" "$test_bin/sqlite3"

cat > "$test_home/.tmux-ai-sessions.json" <<JSON
[{"session_id":"$OLD_ID","agent_type":"codex"}]
JSON

touch "$test_home/.codex/sessions/2026/09/03/rollout-test-$VALID_ID.jsonl"
printf '%s\n' "$VALID_ID" > "$sqlite_output"

HOME="$test_home" PATH="$test_bin:/usr/bin:/bin" SAVE_AI_SQLITE_OUTPUT="$sqlite_output" \
  "$REPO_DIR/scripts/save-ai-sessions.sh" >"$output_file" 2>&1 ||
  fail "persisted ID was rejected"

[ "$(jq -r '.[0].session_id' "$test_home/.tmux-ai-sessions.json")" = "$VALID_ID" ] ||
  fail "did not save the persisted ID"
grep -q "Saved 1/1 sessions (0 missed)" "$output_file" ||
  fail "successful save summary missing"

rm "$test_home/.codex/sessions/2026/09/03/rollout-test-$VALID_ID.jsonl"
printf '%s\n' "$ORPHAN_ID" > "$sqlite_output"
cat > "$test_home/.tmux-ai-sessions.json" <<JSON
[{"session_id":"$OLD_ID","agent_type":"codex"}]
JSON

if HOME="$test_home" PATH="$test_bin:/usr/bin:/bin" SAVE_AI_SQLITE_OUTPUT="$sqlite_output" \
    "$REPO_DIR/scripts/save-ai-sessions.sh" >"$output_file" 2>&1; then
  fail "save succeeded with no resumable rollout"
fi

[ "$(jq -r '.[0].session_id' "$test_home/.tmux-ai-sessions.json")" = "$OLD_ID" ] ||
  fail "existing manifest was overwritten after a failed save"
grep -q "only 0/1 AI sessions have resumable saved state" "$output_file" ||
  fail "strict persistence error missing"
grep -q "session ID $ORPHAN_ID has no saved rollout" "$output_file" ||
  fail "orphan session ID was not reported"
grep -q "Preserving existing manifest" "$output_file" ||
  fail "manifest preservation was not reported"

if HOME="$test_home" PATH="$test_bin:/usr/bin:/bin" SAVE_AI_SQLITE_OUTPUT="$sqlite_output" \
    "$REPO_DIR/scripts/save-ai-sessions.sh" --dry-run >"$output_file" 2>&1; then
  fail "dry run succeeded with no resumable rollout"
fi

echo "PASS: save-ai-sessions rejects orphan IDs and preserves the last good manifest"
