# dotfiles

## Install

```bash
git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

After install:
1. Copy `secrets.example` to `~/.secrets` and fill in your values
2. Run `source ~/.zshrc`
3. Run `claude login`
4. Run `./claude/setup.sh` to configure plugins and MCPs

## Layout

```
bin/                  -> ~/scripts/     # User scripts (in PATH)
  t                                     # tmux session manager
claude/               -> ~/.claude/     # Claude Code config
  commands/                             # Slash commands
  container/                            # Dev container (Dockerfile, build/run scripts)
  settings.json                         # Claude settings
  setup.sh                              # Post-login plugin/MCP setup
scripts/                                # Repo scripts (not installed)
  macos-defaults.sh                     # macOS system preferences
  test-install.sh                       # Installation test
Brewfile                                # Homebrew packages
install.sh                              # Main install script
secrets.example                         # Template for ~/.secrets
tmux.conf             -> ~/.tmux.conf
zshenv                -> ~/.zshenv
zshrc                 -> ~/.zshrc
```

## Commands

**t** - tmux project manager
```bash
t              # list projects
t <name>       # attach or create project
t a            # reattach to last project
t clean        # remove unattached numbered projects
```

## Keybindings (tmux)

| Key | Action |
|-----|--------|
| `Ctrl+Space` | Prefix |
| `Ctrl+t` | New window |
| `Ctrl+Left/Right` | Switch windows |
| `Ctrl+;` | Toggle split pane |
| `prefix + f` | Workmux dashboard |
| `prefix + d` | Detach |
