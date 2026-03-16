#!/usr/bin/env python3
"""Interactive component picker for dotfiles installer.

Uses curses (stdlib) to show a checkbox TUI. Outputs selected component
keys to stdout, one per line — consumed by install.sh.
"""

import curses
import platform
import sys

# (key, label, description, default_mac, default_linux)
COMPONENTS = [
    ("shell",    "Shell config",      "zshrc, zshenv, hushlogin",            True,  True),
    ("tmux",     "Tmux + plugins",    "tmux.conf, tpm, mosh",                True,  True),
    ("scripts",  "Scripts & bin",     "~/scripts/ and ~/bin/ utilities",      True,  True),
    ("homebrew", "Homebrew packages", "CLI tools, casks (macOS only)",        True,  False),
    ("claude",   "Claude settings",   "settings.json, slash commands",        True,  False),
    ("plugins",  "Claude plugins",    "superpowers, dev-browser, PAL MCP",    True,  False),
]

is_mac = platform.system() == "Darwin"


def draw(stdscr, selected, cursor):
    stdscr.clear()
    h, w = stdscr.getmaxyx()
    title = "Dotfiles Installer"
    os_label = "macOS" if is_mac else "Linux"

    # Colors
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_CYAN, -1)     # title
    curses.init_pair(2, curses.COLOR_GREEN, -1)     # selected checkbox
    curses.init_pair(3, curses.COLOR_WHITE, -1)     # description
    curses.init_pair(4, curses.COLOR_YELLOW, -1)    # cursor highlight
    curses.init_pair(5, curses.COLOR_MAGENTA, -1)   # footer

    row = 1
    # Title
    stdscr.attron(curses.color_pair(1) | curses.A_BOLD)
    stdscr.addstr(row, 2, f"  {title}")
    stdscr.attroff(curses.color_pair(1) | curses.A_BOLD)
    row += 1

    stdscr.addstr(row, 2, f"  Detected: {os_label}")
    row += 2

    stdscr.addstr(row, 2, "  Select components to install:")
    row += 2

    # Components
    max_label = max(len(c[1]) for c in COMPONENTS)
    for i, (key, label, desc, _, _) in enumerate(COMPONENTS):
        check = "x" if selected[i] else " "
        is_cursor = i == cursor

        prefix = "  ▸ " if is_cursor else "    "

        if is_cursor:
            attr = curses.color_pair(4) | curses.A_BOLD
        elif selected[i]:
            attr = curses.color_pair(2)
        else:
            attr = curses.color_pair(3)

        line = f"{prefix}[{check}] {label:<{max_label}}   {desc}"
        stdscr.addstr(row, 2, line[:w - 4], attr)
        row += 1

    row += 1
    stdscr.attron(curses.color_pair(5))
    stdscr.addstr(row, 2, "  ↑/↓ navigate   SPACE toggle   a all   n none   ENTER confirm   q quit")
    stdscr.attroff(curses.color_pair(5))

    stdscr.refresh()


def main(stdscr):
    curses.curs_set(0)  # hide cursor

    # Set defaults based on OS
    selected = []
    for _, _, _, mac_default, linux_default in COMPONENTS:
        selected.append(mac_default if is_mac else linux_default)

    cursor = 0
    n = len(COMPONENTS)

    while True:
        draw(stdscr, selected, cursor)
        key = stdscr.getch()

        if key == curses.KEY_UP or key == ord("k"):
            cursor = (cursor - 1) % n
        elif key == curses.KEY_DOWN or key == ord("j"):
            cursor = (cursor + 1) % n
        elif key == ord(" "):
            selected[cursor] = not selected[cursor]
        elif key == ord("a"):
            selected = [True] * n
        elif key == ord("n"):
            selected = [False] * n
        elif key in (curses.KEY_ENTER, 10, 13):
            break
        elif key == ord("q") or key == 27:  # q or ESC
            return []

    return [COMPONENTS[i][0] for i in range(n) if selected[i]]


if __name__ == "__main__":
    # Need a real terminal for the TUI
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("__FALLBACK__")
        sys.exit(0)

    try:
        result = curses.wrapper(main)
    except (curses.error, KeyboardInterrupt):
        print("__FALLBACK__")
        sys.exit(0)

    if not result:
        print("__QUIT__")
    else:
        for key in result:
            print(key)
