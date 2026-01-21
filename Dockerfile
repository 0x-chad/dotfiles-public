FROM node:20-bookworm

# Install dependencies
RUN apt-get update && apt-get install -y \
    zsh git curl jq tmux python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Create user
RUN useradd -m -s /bin/zsh testuser
USER testuser
WORKDIR /home/testuser

# Stubs
RUN mkdir -p ~/.cargo && touch ~/.cargo/env

# Clone and setup dotfiles
RUN git clone https://github.com/0x-chad/dotfiles-public.git ~/dotfiles \
    && cd ~/dotfiles && ./install.sh || true

# Copy secrets and configure PAL
COPY --chown=testuser:testuser secrets /home/testuser/.secrets
RUN grep -E "^export (OPENROUTER_API_KEY|GEMINI_API_KEY|OPENAI_API_KEY)=" ~/.secrets \
    | sed 's/^export //' > ~/pal-mcp-server/.env \
    && echo 'OPENROUTER_ALLOWED_MODELS="google/gemini-2.5-pro,openai/gpt-5-1-codex"' >> ~/pal-mcp-server/.env \
    && echo 'DISABLED_TOOLS=chat,thinkdeep,planner,codereview,precommit,debug,analyze,refactor,testgen,secaudit,docgen,tracer' >> ~/pal-mcp-server/.env \
    && echo 'DEFAULT_MODEL=auto' >> ~/pal-mcp-server/.env \
    && echo 'LOG_LEVEL=INFO' >> ~/pal-mcp-server/.env

# Register plugins and MCP (requires auth token from secrets)
RUN . ~/.secrets && ~/dotfiles/setup-claude.sh

# Entrypoint sources secrets then runs command
COPY --chown=testuser:testuser entrypoint.sh /home/testuser/entrypoint.sh
RUN chmod +x ~/entrypoint.sh

ENTRYPOINT ["/home/testuser/entrypoint.sh"]
CMD ["claude"]
