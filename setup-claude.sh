#!/bin/bash
# Run this AFTER 'claude login' to complete plugin and MCP setup

set -e

echo "=== Claude Post-Login Setup ==="
echo ""

# Check if logged in
if ! claude --version &>/dev/null; then
  echo "Error: Claude CLI not found. Install with: npm i -g @anthropic-ai/claude-code"
  exit 1
fi

# Test auth by trying a simple command
echo "Checking authentication..."
if ! claude mcp list &>/dev/null; then
  echo "Error: Not authenticated. Run 'claude login' first."
  exit 1
fi
echo "✓ Authenticated"
echo ""

# Register local plugin marketplaces
echo "=== Registering Plugin Marketplaces ==="

register_marketplace() {
  local name="$1"
  local path="$2"

  if [[ -d "$path" ]]; then
    echo "Registering $name -> $path"
    claude marketplace add "$name" "$path" 2>/dev/null || echo "  (already registered or failed)"
  else
    echo "Skipping $name (directory not found: $path)"
  fi
}

register_marketplace "superpowers-local" "$HOME/superpowers"
register_marketplace "dev-browser-patchright-marketplace" "$HOME/dev-browser-patchright"
echo ""

# Install plugins
echo "=== Installing Plugins ==="

install_plugin() {
  local plugin="$1"
  echo "Installing $plugin..."
  claude plugin install "$plugin" 2>/dev/null || echo "  (already installed or failed)"
}

# Local plugins (from cloned repos)
install_plugin "superpowers@superpowers-local"
install_plugin "dev-browser@dev-browser-patchright-marketplace"

# Official marketplace plugins
install_plugin "frontend-design@claude-code-plugins"
install_plugin "image-sanitizer@image-sanitizer-marketplace"
install_plugin "ralph-wiggum@claude-code-plugins"
install_plugin "workmux-status@workmux"
echo ""

# Setup MCP servers
echo "=== Configuring MCP Servers ==="

# PAL MCP server (if installed)
PAL_DIR="$HOME/pal-mcp-server"
if [[ -d "$PAL_DIR" ]]; then
  echo "Adding PAL MCP server..."
  claude mcp add pal \
    "$PAL_DIR/.pal_venv/bin/python" \
    "$PAL_DIR/server.py" \
    -e "ENV_FILE=$PAL_DIR/.env" \
    2>/dev/null || echo "  (already configured or failed)"
else
  echo "PAL MCP not found at $PAL_DIR - skipping"
  echo "  To install: git clone <pal-repo> $PAL_DIR"
fi
echo ""

# Verify setup
echo "=== Verification ==="
echo ""
echo "MCP Servers:"
claude mcp list 2>/dev/null || echo "  (none)"
echo ""
echo "Installed Plugins:"
claude plugin list 2>/dev/null | head -20 || echo "  (none)"
echo ""

echo "=== Setup Complete ==="
