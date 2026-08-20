#!/bin/bash
# Shared helpers for recreating missing tmux panes before restoring commands.

tmux_restore_pane_exists() {
  local session="$1" window="$2" pane="$3"
  tmux list-panes -t "=${session}:${window}" -F '#{pane_index}' 2>/dev/null \
    | awk -v pane="$pane" '$0 == pane { found = 1 } END { exit !found }'
}

tmux_restore_window_exists() {
  local session="$1" window="$2"
  tmux list-windows -t "=${session}" -F '#{window_index}' 2>/dev/null \
    | awk -v window="$window" '$0 == window { found = 1 } END { exit !found }'
}

tmux_restore_find_pane() {
  local session="$1" window="$2" window_name="$3" pane="$4"
  local found_window

  if tmux_restore_pane_exists "$session" "$window" "$pane"; then
    printf '=%s:%s.%s\n' "$session" "$window" "$pane"
    return 0
  fi

  found_window=$(tmux list-windows -t "=${session}" -F '#{window_index}|#{window_name}' 2>/dev/null \
    | awk -F '|' -v name="$window_name" '$2 == name { print $1; exit }')
  if [ -n "$found_window" ] && tmux_restore_pane_exists "$session" "$found_window" "$pane"; then
    printf '=%s:%s.%s\n' "$session" "$found_window" "$pane"
    return 0
  fi

  return 1
}

tmux_restore_ensure_pane() {
  local session="$1" window="$2" window_name="$3" pane="$4" cwd="$5"
  local first_window last_pane

  [ -d "$cwd" ] || cwd="$HOME"

  if ! tmux has-session -t "=${session}" 2>/dev/null; then
    tmux new-session -d -s "$session" -n "$window_name" -c "$cwd" zsh
    first_window=$(tmux list-windows -t "=${session}" -F '#{window_index}' 2>/dev/null | head -1)
    if [ -n "$first_window" ] && [ "$first_window" != "$window" ]; then
      tmux move-window -s "=${session}:${first_window}" -t "=${session}:${window}"
    fi
  fi

  if ! tmux_restore_window_exists "$session" "$window"; then
    tmux new-window -d -t "=${session}:${window}" -n "$window_name" -c "$cwd" zsh
  fi

  while ! tmux_restore_pane_exists "$session" "$window" "$pane"; do
    last_pane=$(tmux list-panes -t "=${session}:${window}" -F '#{pane_index}' 2>/dev/null | tail -1)
    [ -n "$last_pane" ] || return 1
    tmux split-window -d -t "=${session}:${window}.${last_pane}" -c "$cwd" zsh
  done
}
