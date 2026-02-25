# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


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

# ---- Helper: choose install executable (avoid wrapper side-effects) ----
cli_bin_for_install() {
  local cli="$1"
  case "$cli" in
    code)
      # Prefer the real VS Code binary during image build.
      # /usr/local/bin/code may be a GUI wrapper script in this project.
      if [[ -x /usr/bin/code ]]; then
        printf '%s\n' "/usr/bin/code"
      else
        command -v code
      fi
      ;;
    code-server)
      command -v code-server
      ;;
    *)
      return 1
      ;;
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
    local cli_bin
    local -a cli_opts=()
    dir="$(ext_dir_for_cli "$cli")"
    cli_bin="$(cli_bin_for_install "$cli")"

    # Ensure the directory exists
    mkdir -p "$dir"

    if [[ "$cli" == "code" && "${EUID}" -eq 0 ]]; then
      local vscode_root_data="/tmp/vscode-root-user-data"
      mkdir -p "$vscode_root_data"
      cli_opts=(--no-sandbox --user-data-dir "$vscode_root_data")
    fi

    echo "Installing extensions via ${cli_bin} (extensions dir: ${dir})..."
    for ext in "${exts[@]}"; do
      if "$cli_bin" "${cli_opts[@]}" --extensions-dir "$dir" --install-extension "$ext"; then
        echo "  ✔ ${ext}"
      else
        echo "  ⚠ Failed to install: ${ext}" >&2
      fi

      if "$cli_bin" "${cli_opts[@]}" --extensions-dir "$dir" --list-extensions | grep -qx "$ext"; then
        echo "  ✔ Verified: ${ext}"
      else
        echo "  ⚠ Not found after install: ${ext}" >&2
      fi
    done

    # Make extension directories writable for non-root runtime user (e.g., coder).
    # Some extensions create runtime files/dirs inside their own extension folder.
    find "$dir" -type d -exec chmod a+w {} +
  done
}

