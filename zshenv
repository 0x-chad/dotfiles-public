. "$HOME/.cargo/env"
export PATH="$HOME/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
# Load secrets (not tracked in git)
[[ -f ~/.secrets ]] && source ~/.secrets
