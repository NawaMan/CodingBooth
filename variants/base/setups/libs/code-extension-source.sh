
# ---- Extension dirs (overridable) ----
# Due to the root (build time) and non-root (coder in this case) (at start time) separation,
#   it is bested to centerize this to the system folder.

# For VS Code desktop (code)
VSCODE_EXTENSION_DIR="${VSCODE_EXTENSION_DIR:-/usr/local/share/code/extensions}"
# For code-server
CODESERVER_EXTENSION_DIR="${CODESERVER_EXTENSION_DIR:-/usr/local/share/code-server/extensions}"

# ---- Helper: pick correct dir for a given CLI ----
ext_dir_for_cli() {
  local cli="$1"
  case "$cli" in
    code)        printf '%s\n' "$VSCODE_EXTENSION_DIR"     ;;
    code-server) printf '%s\n' "$CODESERVER_EXTENSION_DIR" ;;
    *)           return 1 ;;
  esac
}

# ---- Function: install to all available CLIs ----
install_extensions() {
  local -a exts=("$@")
  local -a clis=()

  # Discover available CLIs
  command -v code        >/dev/null 2>&1 && clis+=("code")
  command -v code-server >/dev/null 2>&1 && clis+=("code-server")

  if (( ${#clis[@]} == 0 )); then
    echo "Neither VS Code (code) nor code-server found in PATH." >&2
    return 1
  fi

  # Install each extension to each available CLI
  for cli in "${clis[@]}"; do
    local dir
    dir="$(ext_dir_for_cli "$cli")"

    # Ensure the directory exists
    mkdir -p "$dir"

    echo "Installing extensions via ${cli} (extensions dir: ${dir})..."
    for ext in "${exts[@]}"; do
      if "$cli" --extensions-dir "$dir" --install-extension "$ext" >/dev/null 2>&1; then
        echo "  ✔ ${ext}"
      else
        echo "  ⚠ Failed (or already installed): ${ext}" >&2
      fi
    done
  done
}
