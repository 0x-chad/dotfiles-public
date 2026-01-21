#!/bin/bash
# Dotfiles install script - creates symlinks and installs packages

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing dotfiles ==="

# Symlink dotfiles (portable - no associative arrays)
symlink_file() {
  local src="$1" target="$2"
  local src_path="$DOTFILES_DIR/$src"
  local target_path="$HOME/$target"

  [[ ! -f "$src_path" ]] && echo "Skipping $src (not found)" && return

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    echo "Backing up $target_path -> $target_path.backup"
    mv "$target_path" "$target_path.backup"
  fi

  [[ -L "$target_path" ]] && rm "$target_path"

  echo "Linking $src -> $target_path"
  ln -s "$src_path" "$target_path"
}

symlink_file "zshrc" ".zshrc"
symlink_file "zshenv" ".zshenv"
symlink_file "tmux.conf" ".tmux.conf"

# Claude settings
if [[ -f "$DOTFILES_DIR/claude-settings.json" ]]; then
  mkdir -p ~/.claude
  cp "$DOTFILES_DIR/claude-settings.json" ~/.claude/settings.json
  echo "Copied claude-settings.json -> ~/.claude/settings.json"
fi

# Claude slash commands
if [[ -d "$DOTFILES_DIR/claude-commands" ]]; then
  mkdir -p ~/.claude/commands
  cp "$DOTFILES_DIR/claude-commands/"*.md ~/.claude/commands/ 2>/dev/null
  echo "Copied claude-commands/ -> ~/.claude/commands/"
fi

# Clone and register Claude plugins
echo ""
echo "=== Setting up Claude plugins ==="
clone_plugin() {
  local name="$1"
  local repo="$2"
  local dir="$HOME/$name"

  # Safety check - name must not be empty
  [[ -z "$name" ]] && echo "Error: plugin name is empty" && return 1

  if [[ -d "$dir/.git" ]]; then
    echo "Updating $name..."
    git -C "$dir" pull --ff-only 2>/dev/null || true
  else
    echo "Cloning $name to $dir..."
    [[ -e "$dir" ]] && rm -rf "$dir"
    git clone "https://github.com/$repo.git" "$dir"
  fi
}

clone_plugin "superpowers" "0x-chad/superpowers"
clone_plugin "dev-browser-patchright" "0x-chad/dev-browser-patchright"

echo ""
echo "Plugin repos cloned. After 'claude login', run:"
echo "  ./setup-claude.sh"

# Hushlogin
if [[ -f "$DOTFILES_DIR/hushlogin" ]]; then
  cp "$DOTFILES_DIR/hushlogin" ~/.hushlogin
  echo "Copied hushlogin -> ~/.hushlogin"
fi

# Homebrew packages
echo ""
echo "=== Installing Homebrew packages ==="
if command -v brew &>/dev/null; then
  [[ -f "$DOTFILES_DIR/Brewfile" ]] && brew bundle --file="$DOTFILES_DIR/Brewfile"
else
  echo "Homebrew not installed. Install from https://brew.sh then run:"
  echo "  brew bundle --file=$DOTFILES_DIR/Brewfile"
fi

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. Copy secrets.example to ~/.secrets and fill in your values"
echo "  2. Run 'source ~/.zshrc' to reload shell config"
echo "  3. Run 'claude login' to authenticate"
echo "  4. Run './setup-claude.sh' to install plugins and configure MCPs"
