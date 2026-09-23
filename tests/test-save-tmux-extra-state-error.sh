#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home/scripts" "$test_dir/state"
cp "$REPO_DIR/scripts/save-tmux-extra-state.sh" "$test_dir/home/scripts/"

cat > "$test_dir/home/scripts/save-ai-sessions.sh" <<'STUB'
#!/bin/bash
[ "${FAIL_AI:-0}" != 1 ]
STUB
cat > "$test_dir/home/scripts/save-mosh-sessions.sh" <<'STUB'
#!/bin/bash
[ "${FAIL_MOSH:-0}" != 1 ]
STUB
chmod +x "$test_dir/home/scripts/"*.sh

if HOME="$test_dir/home" TMUX_AUTOSAVE_STATE_DIR="$test_dir/state" FAIL_AI=1 \
  "$test_dir/home/scripts/save-tmux-extra-state.sh"; then
  echo "FAIL: auxiliary save unexpectedly succeeded" >&2
  exit 1
fi

grep -q 'AI session save failed' "$test_dir/state/extra-state-error" || {
  echo "FAIL: auxiliary failure marker was not written" >&2
  exit 1
}

HOME="$test_dir/home" TMUX_AUTOSAVE_STATE_DIR="$test_dir/state" \
  "$test_dir/home/scripts/save-tmux-extra-state.sh"

[ ! -e "$test_dir/state/extra-state-error" ] || {
  echo "FAIL: successful save did not clear auxiliary failure marker" >&2
  exit 1
}

echo "PASS: auxiliary save failures persist until a successful retry"
