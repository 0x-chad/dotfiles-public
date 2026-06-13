#!/bin/bash
# Dotfiles install script - creates symlinks and installs packages
#
# Usage: ./install.sh [basic|full|pick]
#   basic  — shell + tmux + scripts only (good for remote servers)
#   full   — everything: brew packages, Claude plugins, MCP servers
#   pick   — interactive component picker (default)

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────
symlink_file() {
  local src="$1" target="$2"
  local src_path="$DOTFILES_DIR/$src"
  local target_path="$HOME/$target"

  [[ ! -f "$src_path" ]] && echo "  Skipping $src (not found)" && return

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    echo "  Backing up $target_path -> $target_path.backup"
    mv "$target_path" "$target_path.backup"
  fi

  [[ -L "$target_path" ]] && rm "$target_path"

  echo "  Linking $src -> $target_path"
  ln -s "$src_path" "$target_path"
}

clone_plugin() {
  local name="$1"
  local repo="$2"
  local dir="$HOME/$name"

  [[ -z "$name" ]] && echo "  Error: plugin name is empty" && return 1

  if [[ -d "$dir/.git" ]]; then
    echo "  Updating $name..."
    git -C "$dir" pull --ff-only 2>/dev/null || true
  else
    echo "  Cloning $name to $dir..."
    [[ -e "$dir" ]] && rm -rf "$dir"
    git clone "https://github.com/$repo.git" "$dir"
  fi
}

has_component() {
  local target="$1"
  for c in "${COMPONENTS[@]}"; do
    [[ "$c" == "$target" ]] && return 0
  done
  return 1
}

# ── Component install functions ──────────────────────────────────────
install_shell() {
  echo ""
  echo "=== Shell config ==="
  symlink_file "config/zsh/zshrc" ".zshrc"
  symlink_file "config/zsh/zshenv" ".zshenv"
  touch ~/.hushlogin
  echo "  Created ~/.hushlogin"
}

install_tmux() {
  echo ""
  echo "=== Tmux + plugins ==="
  symlink_file "config/tmux/tmux.conf" ".tmux.conf"
  mkdir -p "$HOME/scripts"
  symlink_file "scripts/osc52-copy" "scripts/osc52-copy"

  TPM_DIR="$HOME/.tmux/plugins/tpm"
  if [[ -d "$TPM_DIR/.git" ]]; then
    echo "  tpm already installed"
  else
    echo "  Cloning tpm..."
    mkdir -p "$HOME/.tmux/plugins"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    echo "  tpm installed — run 'prefix + I' inside tmux to install plugins"
  fi

  # Install mosh for persistent remote connections
  if ! command -v mosh &>/dev/null; then
    echo "  Installing mosh..."
    if command -v brew &>/dev/null; then
      brew install mosh
    elif command -v apt-get &>/dev/null; then
      sudo apt-get install -y -qq mosh
    else
      echo "  Skipping mosh (no supported package manager found)"
    fi
  else
    echo "  mosh already installed"
  fi
}

install_scripts() {
  echo ""
  echo "=== Scripts ==="
  [[ -d "$DOTFILES_DIR/scripts" ]] || return
  mkdir -p "$HOME/scripts"
  for script in "$DOTFILES_DIR/scripts/"*; do
    [[ -f "$script" ]] || continue
    name="$(basename "$script")"
    target="$HOME/scripts/$name"
    if [[ -e "$target" && ! -L "$target" ]]; then
      backup="$target.backup-$(date +%Y%m%dT%H%M%S)"
      echo "  Backing up $target -> $backup"
      mv "$target" "$backup"
    fi
    [[ -L "$target" ]] && rm "$target"
    ln -s "$script" "$target"
    echo "  Linking scripts/$name -> ~/scripts/$name"
  done
}

install_tmux_autosave() {
  echo ""
  echo "=== Tmux autosave cron ==="
  local script="$HOME/scripts/tmux-autosave.sh"
  local lock_script="$HOME/scripts/tmux-autosave-lock.sh"
  local log_dir="$HOME/.local/state"

  if [[ ! -x "$script" ]]; then
    echo "  WARNING: autosave script not installed ($script not executable)"
    return
  fi
  if [[ ! -x "$lock_script" ]]; then
    echo "  WARNING: autosave lock script not installed ($lock_script not executable)"
    return
  fi

  mkdir -p "$log_dir"

  # Retire older supervisor-based installs. Cron is the only external scheduler.
  if [[ "$(uname)" == "Darwin" ]]; then
    local label="com.gman.tmux-autosave"
    local plist="$HOME/Library/LaunchAgents/$label.plist"
    launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
    rm -f "$plist"
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now tmux-autosave-monitor.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/tmux-autosave-monitor.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi

  if ! command -v crontab >/dev/null 2>&1; then
    echo "  WARNING: crontab not found; tmux autosave cron not installed"
    return
  fi

  local marker_start="# DOTFILES TMUX AUTOSAVE START"
  local marker_end="# DOTFILES TMUX AUTOSAVE END"
  local reboot_line="@reboot $lock_script"
  local cron_line="*/5 * * * * $script"
  local tmp
  tmp="$(mktemp)"
  ((crontab -l 2>/dev/null || true) | sed "/$marker_start/,/$marker_end/d"; echo "$marker_start"; echo "$reboot_line"; echo "$cron_line"; echo "$marker_end") > "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "  Installed crontab autosave job"
}

install_terminal() {
  echo ""
  echo "=== Terminal config (Option key for tmux prefix) ==="

  # Ghostty
  if [[ -f "$DOTFILES_DIR/config/ghostty/config" ]]; then
    mkdir -p ~/.config/ghostty
    if [[ -e ~/.config/ghostty/config && ! -L ~/.config/ghostty/config ]]; then
      echo "  Backing up ~/.config/ghostty/config -> ~/.config/ghostty/config.backup"
      mv ~/.config/ghostty/config ~/.config/ghostty/config.backup
    fi
    [[ -L ~/.config/ghostty/config ]] && rm ~/.config/ghostty/config
    ln -s "$DOTFILES_DIR/config/ghostty/config" ~/.config/ghostty/config
    echo "  Linked config/ghostty/config -> ~/.config/ghostty/config"
  fi

  # iTerm2 preferences
  if [[ "$(uname)" == "Darwin" && -f "$DOTFILES_DIR/config/iterm2/com.googlecode.iterm2.plist" ]]; then
    mkdir -p ~/.iterm2
    cp "$DOTFILES_DIR/config/iterm2/com.googlecode.iterm2.plist" ~/.iterm2/com.googlecode.iterm2.plist
    defaults import com.googlecode.iterm2 ~/.iterm2/com.googlecode.iterm2.plist
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.iterm2"
    echo "  Copied config/iterm2/ -> ~/.iterm2/ and imported iTerm2 preferences"
  fi

  # Ensure Left Option key sends Esc+ for all currently installed profiles.
  local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  if [[ -f "$plist" ]]; then
    local i=0
    while /usr/libexec/PlistBuddy -c "Print :New\ Bookmarks:$i:Name" "$plist" &>/dev/null; do
      /usr/libexec/PlistBuddy -c "Set :New\ Bookmarks:$i:Option\ Key\ Sends 2" "$plist" 2>/dev/null
      ((i++))
    done
    echo "  Set iTerm2 Left Option key to Esc+ for $i profile(s)"
  else
    echo "  iTerm2 not found, skipping"
  fi
}

install_homebrew() {
  echo ""
  echo "=== Homebrew packages ==="
  if command -v brew &>/dev/null; then
    [[ -f "$DOTFILES_DIR/config/brew/Brewfile" ]] && brew bundle --file="$DOTFILES_DIR/config/brew/Brewfile"
  else
    echo "  Homebrew not installed. Install from https://brew.sh then run:"
    echo "    brew bundle --file=$DOTFILES_DIR/config/brew/Brewfile"
  fi
}

install_claude() {
  echo ""
  echo "=== Claude settings ==="
  if [[ -f "$DOTFILES_DIR/config/claude/settings.json" ]]; then
    mkdir -p ~/.claude
    cp "$DOTFILES_DIR/config/claude/settings.json" ~/.claude/settings.json
    echo "  Copied settings.json -> ~/.claude/settings.json"
  fi

  if [[ -d "$DOTFILES_DIR/config/claude/commands" ]]; then
    mkdir -p ~/.claude/commands
    cp "$DOTFILES_DIR/config/claude/commands/"*.md ~/.claude/commands/ 2>/dev/null
    echo "  Copied slash commands -> ~/.claude/commands/"
  fi
}

install_plugins() {
  echo ""
  echo "=== Claude plugins ==="
  echo "  No extra plugin repositories to clone."
}

# ── Choose what to install ───────────────────────────────────────────
MODE="${1:-}"
COMPONENTS=()

case "$MODE" in
  basic)
    COMPONENTS=(shell tmux scripts)
    ;;
  full)
    COMPONENTS=(shell tmux scripts terminal homebrew claude plugins)
    ;;
  *)
    # Try interactive picker (requires Python 3 + curses)
    if command -v python3 &>/dev/null; then
      PICKER_OUTPUT=$(python3 "$DOTFILES_DIR/picker.py" 2>/dev/null)
      if [[ "$PICKER_OUTPUT" == "__QUIT__" ]]; then
        echo "Cancelled."
        exit 0
      elif [[ "$PICKER_OUTPUT" == "__FALLBACK__" ]] || [[ -z "$PICKER_OUTPUT" ]]; then
        # curses unavailable or terminal too small — fall back to basic/full
        MODE=""
      else
        while IFS= read -r line; do
          COMPONENTS+=("$line")
        done <<< "$PICKER_OUTPUT"
      fi
    fi

    # Fallback: basic/full prompt
    if [[ ${#COMPONENTS[@]} -eq 0 && "$MODE" != "basic" && "$MODE" != "full" ]]; then
      if [[ "$(uname)" == "Darwin" ]]; then
        default=full
      else
        default=basic
      fi
      echo "Detected: $(uname) — defaulting to '$default'"
      echo ""
      echo "Install modes:"
      echo "  1) basic  — shell, tmux, scripts, tpm"
      echo "  2) full   — basic + terminal config, Homebrew packages, Claude plugins, MCP servers"
      echo ""
      read -rp "Choose [1/2] (default: $default): " choice
      case "$choice" in
        1|basic)  COMPONENTS=(shell tmux scripts) ;;
        2|full)   COMPONENTS=(shell tmux scripts terminal homebrew claude plugins) ;;
        "")
          if [[ "$default" == "full" ]]; then
            COMPONENTS=(shell tmux scripts terminal homebrew claude plugins)
          else
            COMPONENTS=(shell tmux scripts)
          fi
          ;;
        *)        echo "Invalid choice"; exit 1 ;;
      esac
    fi
    ;;
esac

if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
  echo "Nothing selected."
  exit 0
fi

echo ""
echo "=== Installing: ${COMPONENTS[*]} ==="

# ── Run selected components ──────────────────────────────────────────
has_component "shell"    && install_shell
has_component "tmux"     && install_tmux
has_component "scripts"  && install_scripts
if has_component "tmux" || has_component "scripts"; then
  install_tmux_autosave
fi
has_component "terminal" && install_terminal
has_component "homebrew" && install_homebrew
has_component "claude"   && install_claude
has_component "plugins"  && install_plugins

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
has_component "shell"   && echo "  • Run 'source ~/.zshrc' to reload shell config"
has_component "tmux"    && echo "  • Open tmux and press 'prefix + I' to install plugins"
has_component "claude"  && echo "  • Run 'claude login' to authenticate"
has_component "plugins" && echo "  • Run './config/claude/setup.sh' to install plugins and configure MCPs"
if has_component "plugins" || has_component "claude"; then
  echo "  • Copy secrets.example to ~/.secrets and fill in your values"
fi
