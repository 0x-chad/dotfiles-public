#!/bin/bash
# Run this AFTER 'claude login' to complete MCP and skill setup

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
echo "MCP Servers:"
claude mcp list 2>/dev/null || echo "  (none)"
echo ""

echo "=== Setup Complete ==="
