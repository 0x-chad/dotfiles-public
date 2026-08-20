# My Setup

![header](https://github.com/0x-chad/dotfiles-public/releases/download/v1.0/unnamed.jpg)



https://github.com/user-attachments/assets/156d40e0-027b-42b4-8ccd-8958629ae648



## Dotfiles
- **Zsh**
  - Minimal prompt with username and directory
  - Shared history across sessions (100k lines)
  - PATH setup for `~/.local/bin`, user scripts, pyenv, fnm when installed, Go, Rust, and Foundry
  - Bare `gws` guard that requires an account-specific wrapper defined locally
- **tmux**
  - `Option+Space` prefix (requires Option/Alt to send Esc+ in your terminal)
  - `t` command for named project sessions
  - Workmux dashboard via `Option+Space f`
  - Auto-start tmux on new terminal tabs and SSH sessions with a real TTY
  - Nested tmux pass-through with `Command+l`
  - Status bar toggle with `Option+Space l`
  - Fast Shift+wheel scrolling and `Option+Space c` scrollback clear
  - `restore-tmux.sh` recreates saved mosh and AI targets when resurrect missed their panes, runs them under zsh, and leaves zsh behind when they exit
- **Terminal**
  - Ghostty config
  - iTerm2/Ghostty Option and Command key mappings for tmux controls
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

`basic` installs required packages when possible: `git`, `zsh`, `tmux`, `mosh`, `python3`, `pip3`, `venv`, `uv`/`uvx`, `node`/`npm`, and `cron`/`crontab`.

Google Workspace CLI setup:
- The public config defines a bare `gws` guard that exits instead of selecting credentials implicitly.
- Run `gws setup-help` (also available as `gws help` or `gws --help`) for the generic multi-account setup instructions.
- Define wrappers for the accounts you actually use in private/local shell config. The wrapper should set a separate `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` and invoke `command gws`.
- Example template:

  ```zsh
  gws_account_name() {
    GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-account_name" command gws "$@"
  }
  ```

  Replace `account_name` with an account identifier and repeat for each account.
- The dotfiles do not install the Google Workspace CLI package or store credentials.

The installer refreshes existing symlinks, but keeps existing regular files in place. Remove a local file first if you want the public dotfiles symlink to replace it.

Node/npm setup:
- macOS installs `fnm` from the Brewfile when Homebrew components are selected. `zshrc` initializes fnm only when it is installed.
- Linux/basic setup uses the system package manager for `node`/`npm`; it does not install fnm.
- Claude and Codex are installed with npm. If the active npm global directory is root-owned, `install.sh` sets npm's global prefix to `~/.local` and installs the CLIs there.
- `~/.local/bin` is intentionally before `/usr/local/bin` and `/usr/bin` so user-owned CLI installs win over stale system/global installs.

Python setup:
- Linux/basic setup installs `python3`, `python3-pip`, `python3-venv`, and `pipx`, then installs `uv` with `pipx` when `uv` is not already available.
- macOS full setup installs `uv` from Homebrew.

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
  codex/config.toml                     # Seeded to ~/.codex/config.toml when missing
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

**Google Workspace CLI**

The bare `gws` command intentionally fails. Define account-specific wrappers in private/local shell config using the template in the setup section, then invoke those wrappers.

## Keybindings (tmux)

| Key | Action |
|-----|--------|
| `Option+Space` | Prefix |
| `Option+Space t` | New window |
| `Option+Space r` | Rename window |
| `Option+Left/Right`, `Command+Left/Right` | Switch windows |
| `Option+Space ;` | Toggle split pane |
| `Option+Space k` | Session picker |
| `Option+k`, `Command+k` | Session picker, including while nested tmux pass-through is active |
| `Option+Space f` | Workmux dashboard |
| `Option+Space l` | Toggle status bar |
| `Option+Space c` | Clear screen and scrollback |
| `Command+0` | Clear screen and scrollback in the active tmux layer |
| `Option+Space d` | Detach |
| `Command+l` | Toggle nested tmux pass-through; hides this session's status bar and sends `Option+Space` to the nested tmux |
