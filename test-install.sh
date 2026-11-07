#!/bin/bash
set -e

echo "=== Testing dotfiles installation ==="
echo ""

# Clone the repo
echo "1. Cloning dotfiles-public..."
git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles
cd ~/dotfiles

# Create mock secrets file (skip if already mounted)
echo "2. Setting up secrets..."
if [[ ! -f ~/.secrets ]]; then
  cat > ~/.secrets << 'EOF'
export CLAUDE_CODE_OAUTH_TOKEN="test-token-not-real"
export HYPERBROWSER_API_KEY="test-key"
export OP_SERVICE_ACCOUNT_TOKEN="test-token"
EOF
  chmod 600 ~/.secrets
  echo "   Created mock ~/.secrets"
else
  echo "   Using existing ~/.secrets"
fi

# Run install (skip brew)
echo ""
echo "3. Running install.sh..."
./install.sh

# Source config
echo ""
echo "4. Testing zsh config..."
source ~/.zshenv

# Check symlinks
echo ""
echo "5. Checking symlinks..."
for f in .zshrc .zshenv .tmux.conf; do
  if [[ -L ~/$f ]]; then
    echo "   ✓ ~/$f -> $(readlink ~/$f)"
  else
    echo "   ✗ ~/$f not linked"
  fi
done

# Check default shell
echo ""
echo "6. Checking default shell..."
expected_shell="$(command -v zsh)"
if command -v getent >/dev/null 2>&1; then
  actual_shell="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
elif command -v dscl >/dev/null 2>&1; then
  actual_shell="$(dscl . -read "/Users/${USER:-$(id -un)}" UserShell | awk '{print $2}')"
else
  actual_shell="${SHELL:-}"
fi
if [[ "$actual_shell" == "$expected_shell" ]]; then
  echo "   ✓ default shell is $actual_shell"
else
  echo "   ✗ default shell is $actual_shell; expected $expected_shell"
  exit 1
fi

# Check env vars
echo ""
echo "7. Checking environment variables..."
for var in CLAUDE_CODE_OAUTH_TOKEN HYPERBROWSER_API_KEY OP_SERVICE_ACCOUNT_TOKEN; do
  if [[ -n "${!var}" ]]; then
    echo "   ✓ $var is set"
  else
    echo "   ✗ $var NOT set"
  fi
done

# Check Claude settings
echo ""
echo "8. Checking Claude config..."
if [[ -f ~/.claude/settings.json ]]; then
  echo "   ✓ settings.json exists"
  echo "   Plugins configured:"
  jq -r '.enabledPlugins | keys[]' ~/.claude/settings.json | sed 's/^/     - /'
else
  echo "   ✗ settings.json missing"
fi

# Check commands
echo ""
echo "9. Checking Claude commands..."
ls ~/.claude/commands/*.md 2>/dev/null | wc -l | xargs -I{} echo "   ✓ {} slash commands installed"

# Check plugin repos cloned
echo ""
echo "10. Checking plugin repos..."
for dir in superpowers; do
  if [[ -d ~/$dir/.git ]]; then
    echo "   ✓ ~/$dir cloned"
  else
    echo "   ✗ ~/$dir not found"
  fi
done

# Test claude CLI
echo ""
echo "11. Testing Claude CLI..."
if claude --version 2>/dev/null; then
  echo "   ✓ Claude CLI works"

  # Run setup-claude.sh with real token
  if [[ "$CLAUDE_CODE_OAUTH_TOKEN" != "test-token-not-real" ]]; then
    echo ""
    echo "12. Running config/claude/setup.sh..."
    cd ~/dotfiles
    ./config/claude/setup.sh

    echo ""
    echo "13. Verifying with Claude..."
    timeout 60 claude -p "list all configured MCP servers and installed plugins, be brief" --print 2>&1
  fi
else
  echo "   ⚠ Claude CLI issue"
fi

echo ""
echo "=== Test complete ==="
