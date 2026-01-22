FROM node:20-bookworm

# Install dependencies (including Playwright/Chromium requirements)
RUN apt-get update && apt-get install -y \
    zsh git curl jq tmux python3 python3-venv python3-pip \
    # Chromium dependencies for dev-browser
    libnspr4 libnss3 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libpango-1.0-0 \
    libcairo2 libdrm2 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Create user
RUN useradd -m -s /bin/zsh testuser
USER testuser
WORKDIR /home/testuser

# Stubs
RUN mkdir -p ~/.cargo && touch ~/.cargo/env

# Set Claude config directory
ENV CLAUDE_CONFIG_DIR=/home/testuser/.claude

# Clone and setup dotfiles
RUN git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles \
    && cd ~/dotfiles && ./install.sh || true

# Copy secrets (credentials come from volume at runtime)
COPY --chown=testuser:testuser secrets /home/testuser/.secrets
RUN grep -E "^export (OPENROUTER_API_KEY|GEMINI_API_KEY|OPENAI_API_KEY)=" ~/.secrets \
    | sed 's/^export //' > ~/pal-mcp-server/.env \
    && echo 'OPENROUTER_ALLOWED_MODELS="google/gemini-2.5-pro,openai/gpt-5-1-codex"' >> ~/pal-mcp-server/.env \
    && echo 'DISABLED_TOOLS=chat,thinkdeep,planner,codereview,precommit,debug,analyze,refactor,testgen,secaudit,docgen,tracer' >> ~/pal-mcp-server/.env \
    && echo 'DEFAULT_MODEL=auto' >> ~/pal-mcp-server/.env \
    && echo 'LOG_LEVEL=INFO' >> ~/pal-mcp-server/.env

# Register plugins and MCP (requires auth token from secrets)
RUN . ~/.secrets && ~/dotfiles/setup-claude.sh

# Pre-install dev-browser dependencies and Chromium for fast startup
RUN cd ~/.claude/plugins/cache/dev-browser-marketplace/dev-browser/*/skills/dev-browser \
    && npm install \
    && npx playwright install chromium

# Entrypoint sources secrets then runs command
COPY --chown=testuser:testuser entrypoint.sh /home/testuser/entrypoint.sh
RUN chmod +x ~/entrypoint.sh

ENTRYPOINT ["/home/testuser/entrypoint.sh"]
CMD ["claude", "--dangerously-skip-permissions"]
