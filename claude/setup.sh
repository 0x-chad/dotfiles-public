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

# Register plugin marketplaces
echo "=== Registering Plugin Marketplaces ==="

add_marketplace() {
  local source="$1"
  echo "Adding marketplace: $source"
  claude plugin marketplace add "$source" 2>&1 | grep -E "(Successfully|already|Failed)" || true
}

# Local marketplaces (from cloned repos)
add_marketplace "$HOME/superpowers"
add_marketplace "$HOME/dev-browser-patchright"

# Remote marketplaces (GitHub repos)
add_marketplace "anthropics/claude-code"
add_marketplace "raine/workmux"
add_marketplace "MussaCharles/claude-code-image-sanitizer"
echo ""

# Install plugins
echo "=== Installing Plugins ==="

install_plugin() {
  local plugin="$1"
  echo "Installing $plugin..."
  claude plugin install "$plugin" 2>&1 | grep -E "(Successfully|already|Failed)" || true
}

# Local plugins (marketplace names are auto-generated from plugin.json)
install_plugin "superpowers@superpowers-dev"
install_plugin "dev-browser@dev-browser-marketplace"

# Remote marketplace plugins
install_plugin "frontend-design@claude-code-plugins"
install_plugin "ralph-wiggum@claude-code-plugins"
install_plugin "workmux-status@workmux"
install_plugin "image-sanitizer@image-sanitizer-marketplace"
echo ""

# Setup MCP servers
echo "=== Configuring MCP Servers ==="

# PAL MCP server
PAL_DIR="$HOME/pal-mcp-server"
if [[ ! -d "$PAL_DIR" ]]; then
  echo "Installing PAL MCP server..."
  git clone https://github.com/BeehiveInnovations/pal-mcp-server "$PAL_DIR"
fi

if [[ -d "$PAL_DIR" ]]; then
  echo "Setting up PAL environment..."
  if [[ -x "$PAL_DIR/run-server.sh" ]]; then
    "$PAL_DIR/run-server.sh" >/dev/null 2>&1 || {
      echo "  Warning: PAL setup encountered issues, continuing..."
    }
  fi

  echo "Adding PAL MCP server to Claude Code..."
  claude mcp add pal \
    -e "ENV_FILE=$PAL_DIR/.env" \
    -- "$PAL_DIR/.pal_venv/bin/python" "$PAL_DIR/server.py" \
    2>&1 | grep -E "(Successfully|already|Failed)" || echo "  ✓ Added"
else
  echo "Error: Failed to set up PAL MCP server"
fi
echo ""

# Verify setup
echo "=== Verification ==="
echo ""
echo "Marketplaces:"
claude plugin marketplace list 2>/dev/null || echo "  (none)"
echo ""
echo "MCP Servers:"
claude mcp list 2>/dev/null || echo "  (none)"
echo ""
echo "Installed Plugins:"
claude plugin list 2>/dev/null || echo "  (none)"
echo ""

echo "=== Setup Complete ==="
