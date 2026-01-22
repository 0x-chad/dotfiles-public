history() { builtin fc -l 1 "$@"; }

### --- Login-only bootstrap (runs only in login shells) ---
if [[ -o login ]]; then
  # Homebrew
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  # pyenv --path belongs in login shell
  export PATH="$HOME/.pyenv/bin:$PATH"
  command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init --path)"
fi

### --- Common PATH & tools (safe in every shell) ---
export PATH="$PATH:$HOME/scripts"

# Go
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin"

# Poetry / local Python tools
export PATH="$HOME/.local/bin:$PATH"

# Foundry & Rust
export PATH="$PATH:$HOME/.foundry/bin"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Yarn global bin
if command -v yarn >/dev/null 2>&1; then
  export PATH="$(yarn global bin):$PATH"
fi

### --- Prompt & colors ---
autoload -U colors && colors
# %n = username, %1~ = last path segment, %F{color} sets color, %f resets
PROMPT="%F{magenta}%n@local:%1~ $ %f"

### --- Aliases ---
alias codex='codex --dangerously-bypass-approvals-and-sandbox "$@"'
alias claude='claude --dangerously-skip-permissions "$@"'
alias claude-fast='ccr code --dangerously-skip-permissions "$@"'
alias python=python3
alias pip=pip3
alias claude-container='docker run -it --rm -v claude-creds:/home/testuser/.claude claude-dev'
alias cc='claude-container'

# Claude container with noVNC (auto-assigns port, prints URL)
ccv() {
  local port=${1:-0}  # 0 = auto-assign
  local container_id
  container_id=$(docker run -d --rm -v claude-creds:/home/testuser/.claude -e NOVNC=1 -e DISPLAY=:99 -p ${port}:6080 claude-dev sleep infinity)
  local assigned_port=$(docker port "$container_id" 6080 | cut -d: -f2)
  echo "noVNC: http://localhost:${assigned_port}"
  docker exec -it -e DISPLAY=:99 "$container_id" claude --dangerously-skip-permissions
  docker stop "$container_id" >/dev/null
}

### --- Claude Code update helper (prevents ENOTEMPTY errors) ---
update-claude() {
  local node_modules="$(npm root -g)"
  local pkg_dir="$node_modules/@anthropic-ai/claude-code"
  local temp_dirs="$node_modules/@anthropic-ai/.claude-code-"*

  echo "Cleaning up any leftover directories..."
  [[ -d "$pkg_dir" ]] && rm -rf "$pkg_dir"
  rm -rf $~temp_dirs 2>/dev/null

  echo "Installing claude-code..."
  npm i -g @anthropic-ai/claude-code
}

### --- pyenv (interactive shell part) ---
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"

### --- Node (fnm - fast node manager) ---
eval "$(fnm env --use-on-cd)"

### --- History (zsh way) ---
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000
setopt APPEND_HISTORY          # append rather than overwrite
setopt INC_APPEND_HISTORY      # write as commands are issued
setopt SHARE_HISTORY           # share across sessions
setopt HIST_IGNORE_DUPS        # ignore duplicate commands
setopt HIST_REDUCE_BLANKS      # trim extra spaces

### --- grep color (GREP_OPTIONS deprecated) ---
export GREP_COLORS="mt=1;35;40"
alias grep='grep --color=always'

### --- Completion & fzf ---
autoload -Uz compinit && compinit
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
fi
# If you use fzf-tab for zsh:
# source ~/fzf-tab-completion/zsh/fzf-zsh-completion.zsh

### --- Git completion (zsh) ---
# zsh's compinit + git already gives you solid completion.
# Otherwise, zsh's compinit + git already gives you solid completion.

### --- Conda (optional) ---
# If you use conda, run `conda init zsh` once and it will add its block here.
# Avoid sourcing the bash-specific hooks.

###############################################################################

# Auto-start tmux for new terminal tabs/SSH sessions
# Each new tab gets its own unique session (numbered 0, 1, 2, etc.)
if [[ -z "$TMUX" ]] && [[ -n "$PS1" ]]; then
  if [[ "$TERM_PROGRAM" == "iTerm.app" || "$TERM_PROGRAM" == "Apple_Terminal" || -n "$SSH_CONNECTION" ]]; then
    tmux new-session
  fi
fi

# Helper: clean unattached numbered tmux sessions, returns count
_tmux_clean_numbered() {
  local deleted=0
  for name in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
    [[ ! "$name" =~ ^[0-9]+$ ]] && continue
    [[ "$(tmux display-message -t "$name" -p '#{session_attached}')" == "1" ]] && continue
    tmux kill-session -t "$name" 2>/dev/null && ((deleted++))
  done
  echo $deleted
}

# t() - Attach or switch to named tmux session
# "t" alone lists sessions, "t <name>" attaches/switches, "t clean" deletes unattached numbered sessions
t() {
  local session="${1:-}"
  if [[ -z "$session" ]]; then
    _tmux_clean_numbered >/dev/null
    tmux ls
  elif [[ "$session" == "clean" ]]; then
    echo "Deleted $(_tmux_clean_numbered) session(s)"
  else
    if [[ -n "$TMUX" ]]; then
      if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -ds "$session" -n main
      fi
      tmux switch-client -t "$session"
      _tmux_clean_numbered >/dev/null
    else
      tmux new-session -As "$session" -n main
    fi
  fi
}

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
