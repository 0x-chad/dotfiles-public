# Setup details

Extra notes for `install.sh`. The short version is in the [README](README.md).

## Google Workspace CLI

- The public config defines a bare `gws` guard that exits instead of selecting credentials implicitly.
- Run `gws setup-help` (also available as `gws help` or `gws --help`) for the generic multi-account setup instructions.
- Define wrappers for the accounts you actually use in private/local shell config. The wrapper should set a separate `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` and invoke `command gws`.
- Example template:

  ```zsh
  gws_account_name() {
    GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-account_name" command gws "$@"
  }
  ```

  Replace `account_name` with an account identifier and repeat for each account.
- The dotfiles do not install the Google Workspace CLI package or store credentials.

## Existing files

The installer refreshes existing symlinks, but keeps existing regular files in place. Remove a local file first if you want the public dotfiles symlink to replace it. The Codex config is the exception: it is never replaced, only merged into by `codex-config-merge`.

## Go

Go is installed in the basic prerequisites; the installer builds muxlight with it.

## Node/npm

- macOS installs `fnm` from the Brewfile when Homebrew components are selected. `zshrc` initializes fnm only when it is installed.
- Linux/basic setup uses the system package manager for `node`/`npm`; it does not install fnm.
- Claude and Codex are installed with npm. If the active npm global directory is root-owned, `install.sh` sets npm's global prefix to `~/.local` and installs the CLIs there.
- `~/.local/bin` is intentionally before `/usr/local/bin` and `/usr/bin` so user-owned CLI installs win over stale system/global installs.

## Python

- Linux/basic setup installs `python3`, `python3-pip`, `python3-venv`, and `pipx`, then installs `uv` with `pipx` when `uv` is not already available.
- macOS installs `uv` from Homebrew.
