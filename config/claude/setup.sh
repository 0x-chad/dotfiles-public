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

# Remote marketplaces (GitHub repos)
add_marketplace "0x-chad/superpowers"
add_marketplace "anthropics/claude-code"
add_marketplace "raine/workmux"
echo ""

# Install plugins
echo "=== Installing Plugins ==="

install_plugin() {
  local plugin="$1"
  echo "Installing $plugin..."
  claude plugin install "$plugin" 2>&1 | grep -E "(Successfully|already|Failed)" || true
}

# Remote marketplace plugins
install_plugin "superpowers@superpowers-dev"
install_plugin "frontend-design@claude-code-plugins"
install_plugin "ralph-wiggum@claude-code-plugins"
install_plugin "workmux-status@workmux"
echo ""

# Install skills
echo "=== Installing Skills ==="
echo "Installing agent-browser..."
npm install -g agent-browser 2>&1 | tail -1 || true
agent-browser install 2>&1 | tail -1 || true
npx skills add vercel-labs/agent-browser 2>&1 | tail -1 || true
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
