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
  symlink_file "zshrc" ".zshrc"
  symlink_file "zshenv" ".zshenv"
  touch ~/.hushlogin
  echo "  Created ~/.hushlogin"
}

install_tmux() {
  echo ""
  echo "=== Tmux + plugins ==="
  symlink_file "tmux.conf" ".tmux.conf"

  TPM_DIR="$HOME/.tmux/plugins/tpm"
  if [[ -d "$TPM_DIR/.git" ]]; then
    echo "  tpm already installed"
  else
    echo "  Cloning tpm..."
    mkdir -p "$HOME/.tmux/plugins"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    echo "  tpm installed — run 'prefix + I' inside tmux to install plugins"
  fi
}

install_scripts() {
  echo ""
  echo "=== Scripts & bin ==="
  for dir in bin scripts; do
    if [[ -d "$DOTFILES_DIR/$dir" ]]; then
      mkdir -p ~/$dir
      for script in "$DOTFILES_DIR/$dir/"*; do
        [[ -f "$script" ]] || continue
        name="$(basename "$script")"
        target="$HOME/$dir/$name"
        [[ -L "$target" ]] && rm "$target"
        ln -s "$script" "$target"
        echo "  Linking $dir/$name -> ~/$dir/$name"
      done
    fi
  done
}

install_homebrew() {
  echo ""
  echo "=== Homebrew packages ==="
  if command -v brew &>/dev/null; then
    [[ -f "$DOTFILES_DIR/Brewfile" ]] && brew bundle --file="$DOTFILES_DIR/Brewfile"
  else
    echo "  Homebrew not installed. Install from https://brew.sh then run:"
    echo "    brew bundle --file=$DOTFILES_DIR/Brewfile"
  fi
}

install_claude() {
  echo ""
  echo "=== Claude settings ==="
  if [[ -f "$DOTFILES_DIR/claude/settings.json" ]]; then
    mkdir -p ~/.claude
    cp "$DOTFILES_DIR/claude/settings.json" ~/.claude/settings.json
    echo "  Copied settings.json -> ~/.claude/settings.json"
  fi

  if [[ -d "$DOTFILES_DIR/claude/commands" ]]; then
    mkdir -p ~/.claude/commands
    cp "$DOTFILES_DIR/claude/commands/"*.md ~/.claude/commands/ 2>/dev/null
    echo "  Copied slash commands -> ~/.claude/commands/"
  fi
}

install_plugins() {
  echo ""
  echo "=== Claude plugins ==="
  clone_plugin "superpowers" "0x-chad/superpowers"
  clone_plugin "dev-browser-patchright" "0x-chad/dev-browser-patchright"
  clone_plugin "pal-mcp-server" "BeehiveInnovations/pal-mcp-server"

  # PAL MCP server venv
  PAL_DIR="$HOME/pal-mcp-server"
  if [[ -d "$PAL_DIR" && ! -d "$PAL_DIR/.pal_venv" ]]; then
    echo "  Setting up PAL MCP server..."
    python3 -m venv "$PAL_DIR/.pal_venv"
    "$PAL_DIR/.pal_venv/bin/pip" install -q -r "$PAL_DIR/requirements.txt" 2>/dev/null || true
  fi

  # PAL .env from secrets
  if [[ -d "$PAL_DIR" && -f "$HOME/.secrets" ]]; then
    echo "  Configuring PAL MCP server..."
    grep -E "^export (OPENROUTER_API_KEY|GEMINI_API_KEY|OPENAI_API_KEY)=" ~/.secrets \
      | sed 's/^export //' > "$PAL_DIR/.env"
    cat >> "$PAL_DIR/.env" << 'EOF'
OPENROUTER_ALLOWED_MODELS="google/gemini-2.5-pro,openai/gpt-5-1-codex"
DISABLED_TOOLS=chat,thinkdeep,planner,codereview,precommit,debug,analyze,refactor,testgen,secaudit,docgen,tracer
DEFAULT_MODEL=auto
LOG_LEVEL=INFO
EOF
    echo "  Created $PAL_DIR/.env"
  fi
}

# ── Choose what to install ───────────────────────────────────────────
MODE="${1:-}"
COMPONENTS=()

case "$MODE" in
  basic)
    COMPONENTS=(shell tmux scripts)
    ;;
  full)
    COMPONENTS=(shell tmux scripts homebrew claude plugins)
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
      echo "  2) full   — basic + Homebrew packages, Claude plugins, MCP servers"
      echo ""
      read -rp "Choose [1/2] (default: $default): " choice
      case "$choice" in
        1|basic)  COMPONENTS=(shell tmux scripts) ;;
        2|full)   COMPONENTS=(shell tmux scripts homebrew claude plugins) ;;
        "")
          if [[ "$default" == "full" ]]; then
            COMPONENTS=(shell tmux scripts homebrew claude plugins)
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
has_component "plugins" && echo "  • Run './claude/setup.sh' to install plugins and configure MCPs"
if has_component "plugins" || has_component "claude"; then
  echo "  • Copy secrets.example to ~/.secrets and fill in your values"
fi
