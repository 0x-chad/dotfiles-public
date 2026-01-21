FROM node:20-bookworm

# Install dependencies
RUN apt-get update && apt-get install -y \
    zsh \
    git \
    curl \
    jq \
    tmux \
    python3 \
    python3-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Create test user
RUN useradd -m -s /bin/zsh testuser
USER testuser
WORKDIR /home/testuser

# Clone dotfiles (will be done at runtime for fresh test)
# Set up minimal stubs
RUN mkdir -p ~/.cargo && touch ~/.cargo/env

# Test script
COPY --chown=testuser:testuser test-install.sh /home/testuser/test-install.sh

ENTRYPOINT ["/bin/bash", "/home/testuser/test-install.sh"]
