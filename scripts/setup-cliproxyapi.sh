#!/usr/bin/env bash
set -euo pipefail

INSTALLER_URL="https://raw.githubusercontent.com/router-for-me/cliproxyapi-installer/refs/heads/master/cliproxyapi-installer"
AUTH_DIR="$HOME/.cli-proxy-api"
CONFIG=""
PROXY_BIN=""
PLATFORM="$(uname -s)"

usage() {
  cat <<'EOF'
Usage: setup-cliproxyapi.sh [--auth]

Installs CLIProxyAPI on Linux or macOS, binds it to localhost, configures
fill-first sticky routing, and writes the private Codex client profile. An
existing ~/.codex/auth.json is imported automatically. Pass --auth to begin
an interactive OAuth login for an additional account.
EOF
}

begin_auth=false
case "${1:-}" in
  "") ;;
  --auth) begin_auth=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

sed_in_place() {
  if [[ "$PLATFORM" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

write_fresh_config() {
  local api_key="$1"
  cat >"$CONFIG" <<EOF
host: "127.0.0.1"
port: 8317
auth-dir: "$AUTH_DIR"
api-keys:
  - "$api_key"
debug: false
routing:
  strategy: "fill-first"
  session-affinity: true
  session-affinity-ttl: "1h"
  session-affinity-subagents: true
EOF
}

configure_linux() {
  command -v systemctl >/dev/null || { echo "systemd user services are required" >&2; exit 1; }
  local installer
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL "$INSTALLER_URL" -o "$installer"
  bash "$installer" install
  CONFIG="$HOME/cliproxyapi/config.yaml"
  PROXY_BIN="$HOME/cliproxyapi/cli-proxy-api"
  [[ -f "$CONFIG" && -x "$PROXY_BIN" ]] || { echo "CLIProxyAPI installation is incomplete" >&2; exit 1; }
}

configure_macos() {
  command -v brew >/dev/null || { echo "Homebrew is required on macOS" >&2; exit 1; }
  brew install cliproxyapi
  CONFIG="$AUTH_DIR/config.yaml"
  local brew_config
  brew_config="$(brew --prefix)/etc/cliproxyapi.conf"
  mkdir -p "$AUTH_DIR"
  [[ -f "$CONFIG" ]] || write_fresh_config "local-codex-$(openssl rand -hex 24)"
  if [[ -f "$brew_config" && ! -L "$brew_config" ]]; then
    mv "$brew_config" "${brew_config}.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  ln -sfn "$CONFIG" "$brew_config"
  PROXY_BIN="$(command -v CLIProxyAPI || command -v cliproxyapi || true)"
  [[ -n "$PROXY_BIN" ]] || { echo "CLIProxyAPI executable was not found after Homebrew install" >&2; exit 1; }
}

case "$PLATFORM" in
  Linux) configure_linux ;;
  Darwin) configure_macos ;;
  *) echo "Unsupported platform: $PLATFORM" >&2; exit 1 ;;
esac

mkdir -p "$AUTH_DIR" "$HOME/.codex"
sed_in_place 's/^host: ""/host: "127.0.0.1"/' "$CONFIG"
sed_in_place 's/^  strategy: "round-robin"/  strategy: "fill-first"/' "$CONFIG"
sed_in_place 's/^  session-affinity: false/  session-affinity: true/' "$CONFIG"
if grep -q 'your-api-key-' "$CONFIG"; then
  sed_in_place "s/your-api-key-[0-9]/$(openssl rand -hex 24)/" "$CONFIG"
fi

api_key=$(sed -n '/^api-keys:/,/^[^[:space:]]/ { s/^[[:space:]]*-[[:space:]]*"\([^"]*\)".*/\1/p; }' "$CONFIG" | head -n 1)
[[ -n "$api_key" ]] || { echo "Could not read a CLIProxyAPI key" >&2; exit 1; }

umask 077
printf 'CLIPROXY_API_KEY=%s\n' "$api_key" >"$AUTH_DIR/client.env"
chmod 600 "$CONFIG" "$AUTH_DIR/client.env"

if [[ -f "$HOME/.codex/auth.json" ]]; then
  command -v node >/dev/null || { echo "node is required to import existing Codex credentials" >&2; exit 1; }
  AUTH_DIR="$AUTH_DIR" node <<'NODE'
const fs = require('fs');
const path = require('path');
const source = JSON.parse(fs.readFileSync(path.join(process.env.HOME, '.codex', 'auth.json'), 'utf8'));
const tokens = source.tokens || {};
for (const key of ['access_token', 'id_token', 'refresh_token', 'account_id']) {
  if (!tokens[key]) throw new Error(`Codex auth is missing ${key}`);
}
let claims = {};
try { claims = JSON.parse(Buffer.from(tokens.id_token.split('.')[1], 'base64url').toString('utf8')); } catch {}
const email = claims.email || `account-${tokens.account_id}`;
const auth = { type: 'codex', email, account_id: tokens.account_id, access_token: tokens.access_token, id_token: tokens.id_token, refresh_token: tokens.refresh_token, last_refresh: source.last_refresh || null, disabled: false, expired: false };
const destination = path.join(process.env.AUTH_DIR, `codex-${tokens.account_id}-${email}.json`);
const temporary = `${destination}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temporary, destination);
fs.chmodSync(destination, 0o600);
console.log('Imported the existing Codex CLI account into CLIProxyAPI.');
NODE
fi

cat >"$HOME/.codex/cliproxy.config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_provider = "cliproxy"

[model_providers.cliproxy]
name = "CLIProxyAPI"
base_url = "http://127.0.0.1:8317/v1"
env_key = "CLIPROXY_API_KEY"
wire_api = "responses"
EOF

case "$PLATFORM" in
  Linux) systemctl --user daemon-reload; systemctl --user enable --now cliproxyapi.service ;;
  Darwin) brew services restart cliproxyapi ;;
esac

for _ in $(seq 1 15); do
  curl -fsS -H "Authorization: Bearer $api_key" http://127.0.0.1:8317/v1/models >/dev/null && break
  sleep 1
done
curl -fsS -H "Authorization: Bearer $api_key" http://127.0.0.1:8317/v1/models >/dev/null

echo "CLIProxyAPI is running at http://127.0.0.1:8317."
echo "Reload zsh with: source ~/.zshrc"
if "$begin_auth"; then
  exec "$PROXY_BIN" --codex-login --no-browser
fi
if [[ -f "$HOME/.codex/auth.json" ]]; then
  echo "Imported the existing Codex login. Add another account with: $PROXY_BIN --codex-login --no-browser"
else
  echo "No existing Codex login found. Add one with: $PROXY_BIN --codex-login --no-browser"
fi
