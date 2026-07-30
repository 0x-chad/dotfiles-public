#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

wait_for_file() {
  local file="$1"
  local attempts=100

  while [ "$attempts" -gt 0 ]; do
    [ -f "$file" ] && return 0
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}

wait_for_line() {
  local file="$1"
  local line="$2"
  local attempts=200

  while [ "$attempts" -gt 0 ]; do
    if [ -f "$file" ] && grep -qx "$line" "$file"; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}

wait_for_session_gone() {
  local socket_name="$1"
  local session_name="$2"
  local attempts=100

  while [ "$attempts" -gt 0 ]; do
    if ! tmux -L "$socket_name" has-session -t "=$session_name" 2>/dev/null; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}

run_case() {
  local case_name="$1"
  local initial_session="$2"
  local saved_session="$3"
  local test_dir socket_name output_file result_file helper_log
  local saved_snapshot

  test_dir="$(mktemp -d)"
  socket_name="restore-bootstrap-${case_name}-$$"
  output_file="$test_dir/output"
  result_file="$test_dir/result"
  helper_log="$test_dir/helpers"
  saved_snapshot="$test_dir/home/.tmux/resurrect/snapshot"

  mkdir -p "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts"
  mkdir -p "$test_dir/home/.tmux/resurrect"
  mkdir -p "$test_dir/scripts"
  ln -s "$REPO_DIR/scripts/restore-tmux.sh" "$test_dir/scripts/restore-tmux.sh"

  if [ -n "$saved_session" ]; then
    printf 'pane\t%s\t0\t1\t:*\t0\ttest\t:/tmp\t1\tzsh\t:\n' "$saved_session" > "$saved_snapshot"
  else
    printf 'pane\tdotfiles\t0\t1\t:*\t0\ttest\t:/tmp\t1\tzsh\t:\n' > "$saved_snapshot"
  fi
  ln -s snapshot "$test_dir/home/.tmux/resurrect/last"

  cat > "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh" <<'RESTORE'
#!/bin/bash
set -euo pipefail

snapshot="$HOME/.tmux/resurrect/last"
while IFS=$'\t' read -r type session_name _; do
  [ "$type" = "pane" ] || continue
  tmux has-session -t "=$session_name" 2>/dev/null ||
    tmux new-session -d -s "$session_name"
done < "$snapshot"

if ! awk -F '\t' '$1 == "pane" && $2 == "0" { found = 1 } END { exit !found }' "$snapshot"; then
  tmux kill-session -t "=0" 2>/dev/null || true
fi
RESTORE
  chmod +x "$test_dir/home/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

  for helper in restore-mosh-sessions.sh restore-ai-sessions.sh tmux-autosave-unlock.sh; do
    cat > "$test_dir/scripts/$helper" <<HELPER
#!/bin/bash
echo "$helper" >> "$helper_log"
HELPER
    chmod +x "$test_dir/scripts/$helper"
  done

  tmux -L "$socket_name" new-session -d -s "$initial_session" \
    "HOME='$test_dir/home' '$test_dir/scripts/restore-tmux.sh' >'$output_file' 2>&1; echo \$? >'$result_file'; exec sleep 30"

  if ! wait_for_line "$helper_log" "tmux-autosave-unlock.sh"; then
    [ ! -f "$output_file" ] || sed -n '1,200p' "$output_file" >&2
    tmux -L "$socket_name" list-sessions 2>/dev/null >&2 || true
    tmux -L "$socket_name" kill-server 2>/dev/null || true
    rm -rf "$test_dir"
    fail "$case_name independent restore worker did not finish"
  fi

  wait_for_session_gone "$socket_name" "restore-recovery" ||
    fail "$case_name recovery session did not remove itself"

  if [ "$saved_session" = "0" ]; then
    tmux -L "$socket_name" has-session -t "=0" 2>/dev/null ||
      fail "$case_name saved session 0 was not restored"
  fi

  if [ "$initial_session" != "0" ] || [ "$saved_session" = "0" ]; then
    wait_for_file "$result_file" || fail "$case_name launcher did not record completion"
    [ "$(cat "$result_file")" = "0" ] || fail "$case_name launcher returned nonzero"
  fi

  grep -qx "restore-mosh-sessions.sh" "$helper_log" ||
    fail "$case_name mosh restore did not run"
  grep -qx "restore-ai-sessions.sh" "$helper_log" ||
    fail "$case_name AI restore did not run"
  grep -qx "tmux-autosave-unlock.sh" "$helper_log" ||
    fail "$case_name autosave unlock did not run"

  tmux -L "$socket_name" kill-server
  rm -rf "$test_dir"
  echo "PASS: $case_name"
}

run_case "without-saved-zero" "0" ""
run_case "with-saved-zero" "0" "0"
run_case "nonzero-bootstrap" "bootstrap" ""
