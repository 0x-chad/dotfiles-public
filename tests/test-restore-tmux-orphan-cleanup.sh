#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
socket_root="$test_dir/tmux-tmp"
socket_path="$socket_root/tmux-$(id -u)/default"
old_server_pid=""

cleanup() {
  TMUX_TMPDIR="$socket_root" tmux kill-server 2>/dev/null || true
  if [ -n "$old_server_pid" ]; then
    kill -KILL "$old_server_pid" 2>/dev/null || true
  fi
  rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts"
mkdir -p "$test_dir/home/.tmux/resurrect"
mkdir -p "$test_dir/scripts"
mkdir -p "$socket_root"
ln -s "$REPO_DIR/scripts/restore-tmux.sh" "$test_dir/scripts/restore-tmux.sh"

printf 'pane\trestored\t0\t1\t:*\t0\ttest\t:/tmp\t1\tzsh\t:\n' \
  > "$test_dir/home/.tmux/resurrect/snapshot"
ln -s snapshot "$test_dir/home/.tmux/resurrect/last"

cat > "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh" <<'RESTORE'
#!/bin/bash
tmux has-session -t '=restored' 2>/dev/null || tmux new-session -d -s restored
RESTORE
chmod +x "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

for helper in restore-mosh-sessions.sh restore-ai-sessions.sh tmux-autosave-unlock.sh; do
  cat > "$test_dir/scripts/$helper" <<'HELPER'
#!/bin/bash
exit 0
HELPER
  chmod +x "$test_dir/scripts/$helper"
done

TMUX_TMPDIR="$socket_root" tmux new-session -d -s orphan 'exec sleep 60'
old_server_pid="$(TMUX_TMPDIR="$socket_root" tmux display-message -p '#{pid}')"
rm "$socket_path"

if ! kill -0 "$old_server_pid" 2>/dev/null; then
  echo "FAIL: orphan fixture server did not survive socket unlink" >&2
  exit 1
fi

output_file="$test_dir/output"
if ! env -u TMUX HOME="$test_dir/home" TMUX_TMPDIR="$socket_root" \
    "$test_dir/scripts/restore-tmux.sh" >"$output_file" 2>&1; then
  sed -n '1,240p' "$output_file" >&2
  echo "FAIL: restore failed after orphan cleanup" >&2
  exit 1
fi

if kill -0 "$old_server_pid" 2>/dev/null; then
  echo "FAIL: unreachable tmux server was not terminated" >&2
  exit 1
fi

grep -q "Found unreachable tmux server PID $old_server_pid" "$output_file" || {
  sed -n '1,240p' "$output_file" >&2
  echo "FAIL: orphan cleanup was not reported" >&2
  exit 1
}

TMUX_TMPDIR="$socket_root" tmux has-session -t '=restored' 2>/dev/null || {
  sed -n '1,240p' "$output_file" >&2
  echo "FAIL: replacement tmux server did not restore the saved session" >&2
  exit 1
}

echo "PASS: unreachable tmux server cleanup"
