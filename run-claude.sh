#!/bin/bash
# Run Claude Code in dev container with persistent credentials
docker run -it --rm -v claude-creds:/home/testuser/.claude claude-dev "$@"
