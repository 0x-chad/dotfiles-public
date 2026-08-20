#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
socket_root="$test_dir/tmux-tmp"

cleanup() {
  TMUX_TMPDIR="$socket_root" tmux kill-server 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts"
mkdir -p "$test_dir/home/.tmux/resurrect"
mkdir -p "$test_dir/scripts"
mkdir -p "$socket_root"
ln -s "$REPO_DIR/scripts/restore-tmux.sh" "$test_dir/scripts/restore-tmux.sh"

printf 'pane\texpected\t0\t1\t:*\t0\tmain\t:/tmp\t1\tzsh\t:\n' \
  > "$test_dir/home/.tmux/resurrect/snapshot"
ln -s snapshot "$test_dir/home/.tmux/resurrect/last"

cat > "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh" <<'RESTORE'
#!/bin/bash
tmux has-session -t '=expected' 2>/dev/null || tmux new-session -d -s expected -n main
RESTORE
chmod +x "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

cat > "$test_dir/home/.tmux-ai-sessions.json" <<'MANIFEST'
[
  {
    "tmux_session": "expected",
    "window_index": 0,
    "window_name": "main",
    "pane_index": 0,
    "agent_type": "codex",
    "session_id": "00000000-0000-0000-0000-000000000000",
    "cwd": "/tmp"
  }
]
MANIFEST

for helper in restore-mosh-sessions.sh restore-ai-sessions.sh; do
  cat > "$test_dir/scripts/$helper" <<'HELPER'
#!/bin/bash
exit 0
HELPER
  chmod +x "$test_dir/scripts/$helper"
done

cat > "$test_dir/scripts/tmux-autosave-unlock.sh" <<HELPER
#!/bin/bash
touch "$test_dir/unlocked"
HELPER
chmod +x "$test_dir/scripts/tmux-autosave-unlock.sh"

output_file="$test_dir/output"
if env -u TMUX HOME="$test_dir/home" TMUX_TMPDIR="$socket_root" \
    "$test_dir/scripts/restore-tmux.sh" >"$output_file" 2>&1; then
  sed -n '1,240p' "$output_file" >&2
  echo "FAIL: restore reported success without a running AI process" >&2
  exit 1
fi

if [ -e "$test_dir/unlocked" ]; then
  echo "FAIL: autosave was unlocked after failed AI verification" >&2
  exit 1
fi

echo "PASS: failed AI resumes keep autosave locked"
