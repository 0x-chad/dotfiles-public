# dotfiles

![header](https://github.com/0x-chad/dotfiles-public/releases/download/v1.0/header.png)

- **Zsh**
  - Minimal prompt with username and directory
  - Shared history across sessions (100k lines)
  - PATH setup for pyenv, fnm, Go, Rust, Foundry
- **tmux**
  - `Ctrl+Space` prefix (easier than `Ctrl+b`)
  - `t` command for named project sessions
  - Workmux dashboard via `Ctrl+Space f`
  - Auto-start tmux on new terminal tabs
- **Claude Code**
  - Plugins: superpowers, frontend-design, dev-browser, workmux-status, image-sanitizer, ralph-wiggum
  - Commands: commit, clean, precommit, consensus, learn, better-prompt
  - MCP servers: PAL, Nansen, mobile-mcp
  - Dev container with noVNC for browser automation
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

After install:
1. Copy `secrets.example` to `~/.secrets` and fill in your values
2. Run `source ~/.zshrc`
3. Run `claude login`
4. Run `./claude/setup.sh` to configure plugins and MCPs

## Layout

```
bin/                  -> ~/bin/         # User scripts (in PATH)
  t                                     # tmux session manager
claude/               -> ~/.claude/     # Claude Code config
  commands/                             # Slash commands
  container/                            # Dev container (Dockerfile, build/run scripts)
  settings.json                         # Claude settings
  setup.sh                              # Post-login plugin/MCP setup
macos-defaults.sh                       # macOS system preferences
test-install.sh                         # Installation test
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
| `Ctrl+Space f` | Workmux dashboard |
| `Ctrl+Space d` | Detach |
