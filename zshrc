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
export PATH="$PATH:$HOME/bin"

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

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
