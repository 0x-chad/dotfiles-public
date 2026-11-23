---
name: herdr-manage
description: Show or hide a tmux window (an agent) in herdr, on this machine or another. Use when asked to promote, activate, restart into, or remove an agent from herdr.
---

# herdr-manage

A herdr space is a tmux session and a tab is a window. This shows or hides one window in herdr. Hiding doesn't stop the agent.

```bash
herdr-manage show <session>:<window>
herdr-manage hide <session>:<window>
herdr-manage list [session]
```

`<window>` is a name or `@id`. The session is always required.

It only acts on the machine it runs on. For another machine, run it there:

```bash
ssh <machine> herdr-manage show <session>:<window>
```

## How it maps

- Agents always run in tmux. `codex`, `claude` and `omp` are aliased to run under muxlight, which reports their status to herdr. Agents started from herdr's + menu go through `herdr-agent`, which puts them in a `<session>:<window>` tmux window.
- herdr's spaces and tabs live in a layout kept by the machine's core, not in any app, so the desktop and phone see the same thing. A terminal labelled `herdr.space=<id>` shows up on its own; an unknown id makes a new space. herdr writes `<space> / <tab>` into each terminal's `where` label.
- Showing a window makes a one-window tmux session `herdr-view-<id>` that links it, plus an `hc` terminal running `tmux attach` to that view, labelled `herdr.window=<id>` so muxlight can find it. `show` writes the space (named after the session, created if missing) and the tab (named after the window) into the layout.
- Names set in herdr are left alone. A space nobody named is called after its repo (the checkout's top folder), else its folder.
- Hiding removes the terminal, the view and the tab. Closing a space's last tab deletes the space. The window and agent are untouched.

An agent started before the last muxlight update keeps the old version and won't report status. Restart it (resume the same session) before showing it.
