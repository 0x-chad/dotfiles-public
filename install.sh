#!/bin/bash
# Dotfiles install script - creates symlinks and installs packages
#
# Usage: ./install.sh [basic|full|pick]
#   basic  — shell + tmux + scripts + Claude/Codex config (+ terminal config on macOS)
#   full   — everything: brew packages, Claude plugins, MCP servers
#   pick   — interactive component picker (default)

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_UPDATED=false

# ── Helpers ──────────────────────────────────────────────────────────
die() {
  echo "ERROR: $*" >&2
  exit 1
}

symlink_file() {
  local src="$1" target="$2"
  local src_path="$DOTFILES_DIR/$src"
  local target_path="$HOME/$target"

  [[ ! -f "$src_path" ]] && echo "  Skipping $src (not found)" && return

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    echo "  Keeping existing $target_path"
    return
  fi

  [[ -L "$target_path" ]] && rm "$target_path"

  echo "  Linking $src -> $target_path"
  ln -s "$src_path" "$target_path"
}

copy_seed_file() {
  local src="$1" target="$2"
  local src_path="$DOTFILES_DIR/$src"
  local target_path="$HOME/$target"

  [[ ! -f "$src_path" ]] && echo "  Skipping $src (not found)" && return

  mkdir -p "$(dirname "$target_path")"

  if [[ -L "$target_path" ]]; then
    local tmp
    tmp="$(mktemp)"
    cp "$target_path" "$tmp"
    rm "$target_path"
    mv "$tmp" "$target_path"
    echo "  Converted $target_path symlink to local file"
    return
  fi

  if [[ -e "$target_path" ]]; then
    echo "  Keeping existing $target_path"
    return
  fi

  cp "$src_path" "$target_path"
  echo "  Copied $src -> $target_path"
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

install_tmux_plugin() {
  local name="$1"
  local repo="$2"
  local dir="$HOME/.tmux/plugins/$name"

  if [[ -d "$dir/.git" ]]; then
    echo "  Updating $name..."
    git -C "$dir" pull --ff-only 2>/dev/null || true
  else
    echo "  Cloning $name..."
    rm -rf "$dir"
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

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "need root privileges to run: $*"
  fi
}

apt_install() {
  if [[ "$APT_UPDATED" != true ]]; then
    run_as_root apt-get update -qq
    APT_UPDATED=true
  fi
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
}

install_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -eq 0 ]] && return 0

  if command -v brew >/dev/null 2>&1; then
    brew install "${packages[@]}"
  elif command -v apt-get >/dev/null 2>&1; then
    apt_install "${packages[@]}"
  else
    die "no supported package manager found; install these packages first: ${packages[*]}"
  fi
}

ensure_command() {
  local command_name="$1"
  local package_name="${2:-$1}"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "  $command_name already installed"
    return 0
  fi

  echo "  Installing $package_name..."
  install_packages "$package_name"
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name still not found after installing $package_name"
}

ensure_crontab() {
  if command -v crontab >/dev/null 2>&1; then
    echo "  crontab already installed"
    return 0
  fi

  echo "  Installing cron..."
  if command -v apt-get >/dev/null 2>&1; then
    apt_install cron
    if command -v systemctl >/dev/null 2>&1; then
      run_as_root systemctl enable --now cron >/dev/null 2>&1 || true
    elif command -v service >/dev/null 2>&1; then
      run_as_root service cron start >/dev/null 2>&1 || true
    fi
  elif command -v brew >/dev/null 2>&1; then
    die "crontab not found; macOS normally provides cron, so install/fix cron before continuing"
  else
    die "crontab not found and no supported package manager is available"
  fi

  command -v crontab >/dev/null 2>&1 || die "crontab still not found after installing cron"
}

ensure_npm() {
  if command -v npm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    echo "  node/npm already installed"
    return 0
  fi

  echo "  Installing node/npm..."
  if command -v brew >/dev/null 2>&1; then
    install_packages node
  elif command -v apt-get >/dev/null 2>&1; then
    apt_install nodejs npm
  else
    die "no supported package manager found; install node/npm first"
  fi

  command -v node >/dev/null 2>&1 || die "node still not found after install"
  command -v npm >/dev/null 2>&1 || die "npm still not found after install"
}

ensure_python_tooling() {
  echo ""
  echo "=== Python tooling ==="

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  Installing python3..."
    if command -v brew >/dev/null 2>&1; then
      install_packages python
    elif command -v apt-get >/dev/null 2>&1; then
      apt_install python3
    else
      die "no supported package manager found; install python3 first"
    fi
  else
    echo "  python3 already installed"
  fi

  if ! command -v pip3 >/dev/null 2>&1; then
    echo "  Installing pip3..."
    if command -v brew >/dev/null 2>&1; then
      install_packages python
    elif command -v apt-get >/dev/null 2>&1; then
      apt_install python3-pip
    else
      die "no supported package manager found; install pip3 first"
    fi
  else
    echo "  pip3 already installed"
  fi

  if ! python3 -m venv --help >/dev/null 2>&1; then
    echo "  Installing python3 venv support..."
    if command -v apt-get >/dev/null 2>&1; then
      apt_install python3-venv
    else
      die "python3 venv support is unavailable; install it with your Python distribution"
    fi
  else
    echo "  python3 venv support already installed"
  fi

  if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
    echo "  uv already installed"
  elif command -v brew >/dev/null 2>&1; then
    echo "  Installing uv..."
    install_packages uv
  elif command -v apt-get >/dev/null 2>&1; then
    if ! command -v pipx >/dev/null 2>&1; then
      echo "  Installing pipx..."
      apt_install pipx
    else
      echo "  pipx already installed"
    fi
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
      echo "  uv already installed"
    else
      echo "  Installing uv with pipx..."
      pipx install uv
    fi
  else
    die "no supported package manager found; install uv first"
  fi

  command -v python3 >/dev/null 2>&1 || die "python3 still not found after install"
  command -v pip3 >/dev/null 2>&1 || die "pip3 still not found after install"
  python3 -m venv --help >/dev/null 2>&1 || die "python3 venv support still unavailable after install"
  command -v uv >/dev/null 2>&1 || die "uv still not found after install"
  command -v uvx >/dev/null 2>&1 || die "uvx still not found after install"
}

ensure_user_npm_prefix() {
  local npm_global_root

  ensure_npm

  npm_global_root="$(npm root -g 2>/dev/null || true)"
  if [ -n "$npm_global_root" ] &&
     { [ -w "$npm_global_root" ] || { [ ! -e "$npm_global_root" ] && [ -w "$(dirname "$npm_global_root")" ]; }; }; then
    return 0
  fi

  mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
  npm config set prefix "$HOME/.local" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
  echo "  Set npm global prefix to ~/.local"
}

install_npm_cli() {
  local command_name="$1"
  local package_name="$2"
  local npm_global_root npm_global_parent npm_prefix npm_bin_dir command_path

  ensure_user_npm_prefix

  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  npm_bin_dir="$npm_prefix/bin"
  command_path="$(command -v "$command_name" 2>/dev/null || true)"

  if [ -n "$command_path" ]; then
    case "$command_path" in
      "$npm_bin_dir"/*)
        echo "  $command_name already installed"
        return 0
        ;;
      *)
        echo "  $command_name exists at $command_path; installing $package_name into $npm_prefix"
        ;;
    esac
  fi

  echo "  Installing $package_name..."
  npm_global_root="$(npm root -g 2>/dev/null || true)"
  npm_global_parent="$(dirname "${npm_global_root:-/}")"
  if { [ -n "$npm_global_root" ] && [ -d "$npm_global_root" ] && [ -w "$npm_global_root" ]; } ||
     { [ -n "$npm_global_root" ] && [ ! -e "$npm_global_root" ] && [ -w "$npm_global_parent" ]; }; then
    npm install -g "$package_name"
  elif command -v sudo >/dev/null 2>&1; then
    sudo env PATH="$PATH" npm install -g "$package_name"
  else
    die "npm global root is not writable and sudo is unavailable: ${npm_global_root:-unknown}"
  fi

  command -v "$command_name" >/dev/null 2>&1 || die "$command_name still not found after installing $package_name"
}

ensure_basic_prereqs() {
  echo ""
  echo "=== Basic prerequisites ==="
  ensure_command git git
  ensure_command zsh zsh
  ensure_command tmux tmux
  ensure_command mosh mosh
  ensure_python_tooling
  ensure_crontab
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
    rm -rf "$TPM_DIR"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    echo "  tpm installed"
  fi
  [[ -f "$TPM_DIR/tpm" ]] || die "tpm was not installed"

  install_tmux_plugin "tmux-resurrect" "tmux-plugins/tmux-resurrect"
  install_tmux_plugin "tmux-continuum" "tmux-plugins/tmux-continuum"
  [[ -x "$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]] || die "tmux-resurrect save script was not installed"
  [[ -d "$HOME/.tmux/plugins/tmux-continuum" ]] || die "tmux-continuum was not installed"

  command -v mosh >/dev/null 2>&1 || die "mosh not found after prerequisite install"
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
      echo "  Keeping existing ~/scripts/$name"
      continue
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
  local log_dir="$HOME/.local/state"

  if [[ ! -x "$script" ]]; then
    echo "  WARNING: autosave script not installed ($script not executable)"
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

  command -v crontab >/dev/null 2>&1 || die "crontab not found; tmux autosave cron cannot be installed"

  local marker_start="# DOTFILES TMUX AUTOSAVE START"
  local marker_end="# DOTFILES TMUX AUTOSAVE END"
  local cron_line="*/5 * * * * $script"
  local cron_tmp
  cron_tmp="$(mktemp)"
  ((crontab -l 2>/dev/null || true) | sed "/$marker_start/,/$marker_end/d"; echo "$marker_start"; echo "$cron_line"; echo "$marker_end") > "$cron_tmp"
  if ! crontab "$cron_tmp"; then
    rm -f "$cron_tmp"
    die "failed to install tmux autosave crontab"
  fi
  rm -f "$cron_tmp"
  echo "  Installed crontab autosave job"
}

set_iterm_key_binding() {
  local plist="$1"
  local profile_index="$2"
  local binding="$3"
  local keycode="$4"
  local text="$5"
  local profile_path=":New\\ Bookmarks:$profile_index"
  local map_path="$profile_path:Keyboard\\ Map"
  local binding_path="$map_path:$binding"

  /usr/libexec/PlistBuddy -c "Print $map_path" "$plist" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c "Add $map_path dict" "$plist" >/dev/null 2>&1 || true

  /usr/libexec/PlistBuddy -c "Delete $binding_path" "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add $binding_path dict" "$plist"
  # Action 10 is iTerm2's "Send Escape Sequence"; Text intentionally excludes
  # the ESC byte because iTerm prepends it for this action.
  /usr/libexec/PlistBuddy -c "Add $binding_path:Action integer 10" "$plist"
  /usr/libexec/PlistBuddy -c "Add $binding_path:Keycode integer $keycode" "$plist"
  /usr/libexec/PlistBuddy -c "Add $binding_path:Modifiers integer 1048576" "$plist"
  /usr/libexec/PlistBuddy -c "Add $binding_path:Text string '$text'" "$plist"
  /usr/libexec/PlistBuddy -c "Add $binding_path:Version integer 1" "$plist"
}

install_terminal() {
  echo ""
  echo "=== Terminal config (Option key for tmux prefix) ==="

  # Ghostty
  if [[ -f "$DOTFILES_DIR/config/ghostty/config" ]]; then
    mkdir -p ~/.config/ghostty
    if [[ -e ~/.config/ghostty/config && ! -L ~/.config/ghostty/config ]]; then
      echo "  Keeping existing ~/.config/ghostty/config"
    else
      [[ -L ~/.config/ghostty/config ]] && rm ~/.config/ghostty/config
      ln -s "$DOTFILES_DIR/config/ghostty/config" ~/.config/ghostty/config
      echo "  Linked config/ghostty/config -> ~/.config/ghostty/config"
    fi
  fi

  # iTerm2 preferences
  if [[ "$(uname)" == "Darwin" && -f "$DOTFILES_DIR/config/iterm2/com.googlecode.iterm2.plist" ]]; then
    mkdir -p ~/.iterm2
    if [[ -e ~/.iterm2/com.googlecode.iterm2.plist ]]; then
      echo "  Keeping existing ~/.iterm2/com.googlecode.iterm2.plist"
    else
      cp "$DOTFILES_DIR/config/iterm2/com.googlecode.iterm2.plist" ~/.iterm2/com.googlecode.iterm2.plist
      defaults import com.googlecode.iterm2 ~/.iterm2/com.googlecode.iterm2.plist
      defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
      defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.iterm2"
      echo "  Copied config/iterm2/ -> ~/.iterm2/ and imported iTerm2 preferences"
    fi
  fi

  # Ensure Left Option key sends Esc+ for all currently installed profiles.
  local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  if [[ -f "$plist" ]]; then
    local i=0
    while /usr/libexec/PlistBuddy -c "Print :New\ Bookmarks:$i:Name" "$plist" &>/dev/null; do
      /usr/libexec/PlistBuddy -c "Set :New\ Bookmarks:$i:Option\ Key\ Sends 2" "$plist" 2>/dev/null
      set_iterm_key_binding "$plist" "$i" "0x6b-0x100000-0x28" 40 "k"
      set_iterm_key_binding "$plist" "$i" "0x6c-0x100000-0x25" 37 "l"
      set_iterm_key_binding "$plist" "$i" "0x30-0x100000-0x1d" 29 " c"
      set_iterm_key_binding "$plist" "$i" "0xf702-0x100000-0x7b" 123 "[1;3D"
      set_iterm_key_binding "$plist" "$i" "0xf703-0x100000-0x7c" 124 "[1;3C"
      ((i++))
    done
    echo "  Set iTerm2 Option and Command key tmux mappings for $i profile(s)"
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
  echo "=== Claude CLI + settings ==="
  install_npm_cli claude "@anthropic-ai/claude-code"

  if [[ -f "$DOTFILES_DIR/config/claude/settings.json" ]]; then
    mkdir -p ~/.claude
    if [[ -e ~/.claude/settings.json ]]; then
      echo "  Keeping existing ~/.claude/settings.json"
    else
      cp "$DOTFILES_DIR/config/claude/settings.json" ~/.claude/settings.json
      echo "  Copied settings.json -> ~/.claude/settings.json"
    fi
  fi

  if [[ -d "$DOTFILES_DIR/config/claude/commands" ]]; then
    mkdir -p ~/.claude/commands
    for command_file in "$DOTFILES_DIR/config/claude/commands/"*.md; do
      [[ -f "$command_file" ]] || continue
      command_name="$(basename "$command_file")"
      if [[ -e "$HOME/.claude/commands/$command_name" ]]; then
        echo "  Keeping existing ~/.claude/commands/$command_name"
      else
        cp "$command_file" "$HOME/.claude/commands/$command_name"
        echo "  Copied $command_name -> ~/.claude/commands/"
      fi
    done
  fi
}

install_codex() {
  echo ""
  echo "=== Codex CLI + settings ==="
  install_npm_cli codex "@openai/codex"

  if [[ -f "$DOTFILES_DIR/config/codex/config.toml" ]]; then
    copy_seed_file "config/codex/config.toml" ".codex/config.toml"
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
    COMPONENTS=(shell tmux scripts claude codex)
    if [[ "$(uname)" == "Darwin" ]]; then
      COMPONENTS+=(terminal)
    fi
    ;;
  full)
    COMPONENTS=(shell tmux scripts terminal homebrew claude codex plugins)
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
      echo "  1) basic  — shell, tmux, scripts, tpm, Claude/Codex config; terminal config on macOS"
      echo "  2) full   — basic + terminal config, Homebrew packages, Claude/Codex config, plugins, MCP servers"
      echo ""
      read -rp "Choose [1/2] (default: $default): " choice
      case "$choice" in
        1|basic)
          COMPONENTS=(shell tmux scripts claude codex)
          if [[ "$(uname)" == "Darwin" ]]; then
            COMPONENTS+=(terminal)
          fi
          ;;
        2|full)   COMPONENTS=(shell tmux scripts terminal homebrew claude codex plugins) ;;
        "")
          if [[ "$default" == "full" ]]; then
            COMPONENTS=(shell tmux scripts terminal homebrew claude codex plugins)
          else
            COMPONENTS=(shell tmux scripts claude codex)
            if [[ "$(uname)" == "Darwin" ]]; then
              COMPONENTS+=(terminal)
            fi
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
if has_component "shell" || has_component "tmux" || has_component "scripts"; then
  ensure_basic_prereqs
fi
has_component "shell"    && install_shell
has_component "tmux"     && install_tmux
has_component "scripts"  && install_scripts
if has_component "tmux" || has_component "scripts"; then
  install_tmux_autosave
fi
has_component "terminal" && install_terminal
has_component "homebrew" && install_homebrew
has_component "claude"   && install_claude
has_component "codex"    && install_codex
has_component "plugins"  && install_plugins

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
has_component "shell"   && echo "  • Run 'source ~/.zshrc' to reload shell config"
has_component "tmux"    && echo "  • Restart tmux or run 'tmux source-file ~/.tmux.conf' to load config changes"
has_component "claude"  && echo "  • Run 'claude login' to authenticate"
has_component "codex"   && echo "  • Run 'codex login' to authenticate"
has_component "plugins" && echo "  • Run './config/claude/setup.sh' to install plugins and configure MCPs"
if has_component "plugins" || has_component "claude"; then
  echo "  • Copy secrets.example to ~/.secrets and fill in your values"
fi
