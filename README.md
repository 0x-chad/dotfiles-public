# My Setup

![header](https://github.com/0x-chad/dotfiles-public/releases/download/v1.0/unnamed.jpg)



https://github.com/user-attachments/assets/156d40e0-027b-42b4-8ccd-8958629ae648



## Dotfiles
- **Zsh**
  - Minimal prompt with username and directory
  - Shared history across sessions (100k lines)
  - PATH setup for pyenv, fnm, Go, Rust, Foundry, and `~/.local/bin`
  - `gws-work` / `gws-personal` aliases for separate Google Workspace CLI profiles
- **tmux**
  - `Option+Space` prefix (requires Option/Alt to send Esc+ in your terminal)
  - `t` command for named project sessions
  - Workmux dashboard via `Option+Space f`
  - Auto-start tmux on new terminal tabs and SSH sessions with a real TTY
  - Nested tmux pass-through with `Command+l`
  - Status bar toggle with `Option+Space l`
  - Fast Shift+wheel scrolling and `Option+Space c` scrollback clear
- **Terminal**
  - Ghostty config
  - iTerm2 Option-key setup for the tmux prefix
- **Claude Code**
  - Plugins: superpowers, frontend-design, workmux-status, ralph-wiggum
  - Skills: agent-browser
  - Commands: commit, clean, precommit, consensus, learn, better-prompt
  - Dev container with noVNC for browser automation
- **Codex**
  - Public agent limits: 20 parallel threads, depth 3
- **Brewfile**
  - Terminal: tmux, mosh, fzf, jq
  - Git: gh CLI, git-lfs
  - Languages: fnm (Node), pyenv (Python)
  - DevOps: terraform, kubectl, helm, minikube
  - Workflow: workmux, yabai (tiling WM)
  - Apps: 1password-cli, maccy (clipboard), hiddenbar

## Install

```bash
git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Install modes:

```bash
./install.sh basic  # shell, tmux, scripts, Claude/Codex CLIs + config, autosave; terminal config on macOS
./install.sh full   # basic + Homebrew, Claude/Codex plugins
./install.sh pick   # interactive component picker
```

`basic` installs required packages when possible: `git`, `zsh`, `tmux`, `mosh`, `node`/`npm`, and `cron`/`crontab`.

After install:
1. Copy `secrets.example` to `~/.secrets` and fill in your values
2. Run `source ~/.zshrc`
3. Run `claude login`
4. Run `./config/claude/setup.sh` to configure plugins and MCPs

## Layout

```
config/
  brew/Brewfile                         # Homebrew packages
  claude/             -> ~/.claude/     # Claude Code config
    commands/                           # Slash commands
    container/                          # Dev container (Dockerfile, build/run scripts)
    settings.json                       # Claude settings
    setup.sh                            # Post-login plugin/MCP setup
  codex/config.toml   -> ~/.codex/config.toml
  ghostty/config      -> ~/.config/ghostty/config
  iterm2/com.googlecode.iterm2.plist    # iTerm2 preferences
  osx/osx-config.sh                     # macOS system preferences
  tmux/tmux.conf      -> ~/.tmux.conf
  zsh/zshenv          -> ~/.zshenv
  zsh/zshrc           -> ~/.zshrc
scripts/              -> ~/scripts/     # User scripts (in PATH)
  osc52-copy                            # tmux clipboard helper
  t                                     # tmux session manager
test-install.sh                         # Installation test
install.sh                              # Main install script
secrets.example                         # Template for ~/.secrets
```

## Commands

**t** - tmux project manager
```bash
t              # list projects
t <name>       # attach or create project
t --select     # pick a session with fzf and run normal cleanup
t a            # reattach to last project
t clean        # remove unattached numbered projects
```

## Keybindings (tmux)

| Key | Action |
|-----|--------|
| `Option+Space` | Prefix |
| `Option+Space t` | New window |
| `Option+Space r` | Rename window |
| `Option+Left/Right`, `Command+Left/Right` | Switch windows |
| `Option+Space ;` | Toggle split pane |
| `Option+Space k` | Session picker |
| `Option+k` | Session picker, including while nested tmux pass-through is active |
| `Option+Space f` | Workmux dashboard |
| `Option+Space l` | Toggle status bar |
| `Option+Space c` | Clear screen and scrollback |
| `Command+0` | Clear screen and scrollback in the active tmux layer |
| `Option+Space d` | Detach |
| `Command+l` | Toggle nested tmux pass-through; hides this session's status bar and sends `Option+Space` to the nested tmux |
