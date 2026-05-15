#!/bin/bash
# repair-tmux-resurrect-mosh.sh — Fix malformed mosh pane rows in resurrect saves.
#
# tmux-resurrect parses pane rows with bash `read` using tab as IFS. If
# #{pane_title} is empty, bash collapses that empty field and shifts the rest of
# the row left. For mosh panes that turns the saved full command into ":" and
# makes restore impossible. This hook runs immediately after the layout file is
# written, while the mosh process is still alive, and reconstructs the command.

set -euo pipefail

file="${1:-}"
[ -n "$file" ] && [ -f "$file" ] || exit 0

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

full_command_for_pane_pid() {
  local pane_pid="$1"
  ps -ao "ppid,args" |
    sed "s/^ *//" |
    awk -v pid="$pane_pid" '$1 == pid {sub(/^[^ ]+ /, ""); print; exit}'
}

while IFS= read -r line; do
  if [[ "$line" == pane$'\t'* ]]; then
    IFS=$'\t' read -r -a fields <<< "$line"

    # Shifted row shape:
    # pane session window active flags pane_index :path active mosh-client pane_pid :
    if [ "${#fields[@]}" -eq 11 ] &&
       [ "${fields[8]}" = "mosh-client" ] &&
       [[ "${fields[9]}" =~ ^[0-9]+$ ]] &&
       [ "${fields[10]}" = ":" ]; then
      full_command=$(full_command_for_pane_pid "${fields[9]}" || true)
      if [ -n "$full_command" ]; then
        printf 'pane\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t:%s\n' \
          "${fields[1]}" "${fields[2]}" "${fields[3]}" "${fields[4]}" "${fields[5]}" \
          ":" "${fields[6]}" "${fields[7]}" "${fields[8]}" "$full_command" >> "$tmp"
        continue
      fi
    fi
  fi

  printf '%s\n' "$line" >> "$tmp"
done < "$file"

mv "$tmp" "$file"
trap - EXIT
