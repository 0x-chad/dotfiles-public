# My Setup

![header](https://github.com/0x-chad/dotfiles-public/releases/download/v1.0/unnamed.jpg)



https://github.com/user-attachments/assets/156d40e0-027b-42b4-8ccd-8958629ae648



## Architecture

Public (this repo) is the base for every machine and holds nothing machine-specific: no hostnames, accounts or secrets. An optional private repo at `~/dotfiles-private` holds only what public can't, and never duplicates a public file.

- Static files (`zshrc`, `tmux.conf`, scripts) are symlinked from public.
- Local additions go in `~/.zshrc.local` and `~/.zshenv.local`, sourced last if present.
- Config a tool rewrites itself (Codex) is merged key by key by `codex-config-merge`, never symlinked or copied.

## Install

```bash
git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles-public
cd ~/dotfiles-public
./install.sh
```

Install modes:

```bash
./install.sh basic  # shell, tmux, scripts, Claude/Codex CLIs + config, autosave; terminal config on macOS
./install.sh full   # basic + Homebrew
./install.sh pick   # interactive component picker
```

`basic` installs required packages when possible: `git`, `zsh`, `tmux`, `mosh`, `go`, `python3`, `pip3`, `venv`, `uv`/`uvx`, `node`/`npm`, and `cron`/`crontab`.

Setup details (existing files, Go/Node/Python, Google Workspace CLI wrappers): [SETUP.md](SETUP.md).

After install:
1. Copy `secrets.example` to `~/.secrets` and fill in your values
2. Run `source ~/.zshrc`
3. Run `claude login`

### Optional: CLIProxyAPI for Codex

On Linux or macOS, install a localhost-only CLIProxyAPI pool with:

```bash
~/dotfiles-public/scripts/setup-cliproxyapi.sh
source ~/.zshrc
```

The helper imports an existing `~/.codex/auth.json` automatically. Add any
additional Codex accounts separately, keeping OAuth credentials private:

```bash
~/cliproxyapi/cli-proxy-api --codex-login --no-browser
```

The helper uses the upstream CLIProxyAPI installer on Linux and Homebrew on
macOS, configures `fill-first` session-affinity routing, and sets
the proxy as Codex's **default** provider, so a bare `codex` uses the pool
with no wrapper and no `--profile` flag. On Linux it runs the proxy as a systemd user
service with lingering enabled, so it survives logout and reboot on headless
hosts. It never copies account files, refresh tokens, or API keys into this
repository. The proxy binds 127.0.0.1 and serves local callers without an
API key, so nothing has to thread a shared secret through shell config.

## Layout

```
config/
  brew/Brewfile                         # Homebrew packages
  claude/             -> ~/.claude/     # Claude Code config
    commands/                           # Slash commands
    settings.json                       # Claude settings
  codex/config.toml                     # Shared keys, merged into ~/.codex/config.toml
  herdr/programs.json -> ~/.config/herdr-app/programs.json
  ghostty/config      -> ~/.config/ghostty/config
  iterm2/com.googlecode.iterm2.plist    # iTerm2 preferences
  osx/osx-config.sh                     # macOS system preferences
  tmux/tmux.conf      -> ~/.tmux.conf
  zsh/zshenv          -> ~/.zshenv
  zsh/zshrc           -> ~/.zshrc
scripts/              -> ~/scripts/     # User scripts (in PATH)
  osc52-copy                            # tmux clipboard helper
  codex-config-merge                    # merge shared Codex config into the live one (needs uv)
  herdr-agent, herdr-focus              # herdr + tmux integration
  t                                     # tmux session manager
test-install.sh                         # Installation test
install.sh                              # Main install script
SETUP.md                                # Setup details: gws, Go/Node/Python, existing files
secrets.example                         # Template for ~/.secrets
```

## Commands

**t** - tmux project manager
```bash
t              # list projects
t <name>       # attach or create project
t --select     # pick a session with fzf and run normal cleanup (hides herdr-view- sessions)
t --select --all  # include the herdr view sessions
t a            # reattach to last project
t clean        # remove unattached numbered projects
```

**codex-config-merge** - apply the shared Codex config
```bash
codex-config-merge --dry-run   # show the diff, write nothing
codex-config-merge             # merge; previous file kept as config.toml.bak-<pid>
codex-config-merge --overlay ~/dotfiles-private/config/codex/config.toml   # then machine-local settings
```
Every key the shared file sets is applied; every other key is left alone. tomlkit is resolved by `uv`, so nothing is installed system-wide.

**Google Workspace CLI**

The bare `gws` command intentionally fails. Define account-specific wrappers in private/local shell config using the template in [SETUP.md](SETUP.md), then invoke those wrappers.

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
| `Option+Space l` | Toggle status bar |
| `Option+Space c` | Clear screen and scrollback |
| `Command+0` | Clear screen and scrollback in the active tmux layer |
| `Option+Space d` | Detach |
| `Command+l` | Toggle nested tmux pass-through; hides this session's status bar and sends `Option+Space` to the nested tmux |

## Dotfiles
- **Zsh**
  - Minimal prompt with username and directory
  - Sets Zsh as the user's default login shell during installation
  - Shared history across sessions (100k lines)
  - PATH setup for `~/.local/bin`, user scripts, pyenv, fnm when installed, Go, Rust, and Foundry
  - Bare `gws` guard that requires an account-specific wrapper defined locally
  - Machine-local overlays: `~/.zshrc.local` (interactive) and `~/.zshenv.local` (every shell, including scripts and cron) are sourced last when present
- **tmux**
  - `Option+Space` prefix (requires Option/Alt to send Esc+ in your terminal)
  - `t` command for named project sessions
  - Auto-start tmux on new terminal tabs and SSH sessions with a real TTY
  - Nested tmux pass-through with `Command+l`
  - Status bar toggle with `Option+Space l`
  - Fast Shift+wheel scrolling and `Option+Space c` scrollback clear
  - `set-titles` labels the terminal tab with the session and window name
  - `restore-tmux.sh` recreates saved mosh and AI targets when resurrect missed their panes, runs them under zsh, and leaves zsh behind when they exit
- **Terminal**
  - Ghostty config
  - iTerm2/Ghostty Option and Command key mappings for tmux controls
- **Claude Code**
  - Session retention set to 3,650,000 days (effectively disables automatic age-based pruning)
  - Commands: commit, clean, precommit, consensus, learn, better-prompt
- **Codex**
  - One shared config for every machine: model, reasoning effort, approval/sandbox policy, feature flags, plugin state, providers, agent limits (20 threads, depth 3)
  - Applied by `codex-config-merge`, which merges keys into `~/.codex/config.toml` instead of copying, so trusted projects and other state Codex writes itself survive
  - Optional localhost-only CLIProxyAPI pool for multiple Codex OAuth accounts
- **herdr**
  - Agents run under [muxlight](https://github.com/0x-chad/muxlight), built from source by the installer (needs Go), so their status reaches herdr through tmux
  - `herdr-agent` starts an agent from herdr's `+` menu in a named tmux window, reachable from herdr or a plain `tmux attach`
  - `herdr-focus` picks which running agents get a herdr tab; set `HERDR_FOCUS_MACHINE` and `HERDR_FOCUS_SESSION` in `~/.zshenv.local`
  - `config/herdr/programs.json` defines the `+` menu entries
- **Brewfile**
  - Terminal: tmux, mosh, fzf, jq
  - Git: gh CLI, git-lfs
  - Languages: fnm (Node), pyenv (Python)
  - DevOps: terraform, kubectl, helm, minikube
  - Apps: 1password-cli, maccy (clipboard), hiddenbar
