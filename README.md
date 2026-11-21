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

### Optional: CLIProxyAPI for Codex

`scripts/setup-cliproxyapi.sh` installs a localhost-only proxy that pools multiple Codex OAuth accounts and makes it Codex's default provider. It imports `~/.codex/auth.json`; add more accounts with `~/cliproxyapi/cli-proxy-api --codex-login --no-browser`. No credentials are stored in this repo.

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
  herdr-agent, herdr-manage             # herdr + tmux integration
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
