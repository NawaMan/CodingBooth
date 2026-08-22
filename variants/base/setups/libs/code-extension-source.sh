# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# ---- QEMU detection ----
# When cross-building arm64 on amd64 (or vice versa), code-server's bundled
# Node binary fails with "Invalid ELF image".  Extension installs must be
# deferred to first launch on real hardware.
is_qemu() { [ -e /dev/.buildkit_qemu_emulator ]; }

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
# ---- The two editors do NOT share a registry ----
# Desktop VS Code resolves against the Microsoft Marketplace (its product.json
# serviceUrl); code-server resolves against Open VSX. The publisher namespaces are
# independent, so the correct id for the *same* extension is often different, and an
# id can be absent from one registry entirely:
#
#   ElixirLS   elixir-lsp.elixir-ls on Open VSX;  JakeBecker.elixir-ls on the
#              Marketplace — where elixir-lsp.elixir-ls is a DEPRECATED stub, so
#              the wrong id installs the wrong package rather than failing.
#   C#         ms-dotnettools.csharp is Marketplace-only (Microsoft-licensed).
#
# Use install_extensions for ids that are the same on both, and the per-editor
# functions below when they diverge. Naming an id an editor cannot resolve is not
# an error here — this function warns and carries on (see docs/TODO.md).

# install_extensions <ids...>
#   Install into every editor found. For ids that resolve on both registries.
install_extensions() {
  local found=""
  command -v code        >/dev/null 2>&1 && found="${found} code"
  command -v code-server >/dev/null 2>&1 && found="${found} code-server"
  _install_extensions_into "${found}" "$@"
}

# install_vscode_extensions <ids...>
#   Desktop VS Code only — ids as published on the Microsoft Marketplace.
#   A no-op when the image has no `code` (e.g. the codeserver variant).
install_vscode_extensions() {
  if ! command -v code >/dev/null 2>&1; then
    echo "VS Code (code) not installed — skipping VS Code-only extensions: $*" >&2
    return 0
  fi
  _install_extensions_into "code" "$@"
}

# install_codeserver_extensions <ids...>
#   code-server only — ids as published on Open VSX.
#   A no-op when the image has no code-server (e.g. the desktop variants).
install_codeserver_extensions() {
  if ! command -v code-server >/dev/null 2>&1; then
    echo "code-server not installed — skipping code-server-only extensions: $*" >&2
    return 0
  fi
  _install_extensions_into "code-server" "$@"
}

# _install_extensions_into "<cli> [<cli>]" <ids...>
#   Shared machinery for the three entry points above. The CLI list is one
#   space-separated argument (CLI names contain no spaces), which keeps the ids in
#   "$@" where the original loop expects them. Behavior is otherwise unchanged from
#   the single-function install_extensions this was factored out of.
_install_extensions_into() {
  # shellcheck disable=SC2206  # deliberate word-split of the CLI list
  local -a clis=($1); shift
  local -a exts=("$@")

  if (( ${#clis[@]} == 0 )); then
    echo "Neither VS Code (code) nor code-server found in PATH." >&2
    return 1
  fi

  # Under QEMU, code-server's bundled Node cannot run — skip gracefully.
  if is_qemu; then
    echo "⚠️  QEMU detected — deferring extension install to first launch." >&2
    return 0
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

    # cli_opts is empty for every CLI but root-run `code`, and the
    # ${cli_opts[@]+"..."} form is what makes that safe: under `set -u` bash 3.2
    # — what macOS ships — a plain "${cli_opts[@]}" on an empty array counts as
    # an unbound variable and aborts. Booths run bash 5, so this only shows when
    # a test runs this script on a Mac host.
    echo "Installing extensions via ${cli_bin} (extensions dir: ${dir})..."
    for ext in "${exts[@]}"; do
      if "$cli_bin" ${cli_opts[@]+"${cli_opts[@]}"} --extensions-dir "$dir" --install-extension "$ext"; then
        echo "  ✔ ${ext}"
      else
        echo "  ⚠ Failed to install: ${ext}" >&2
      fi

      if "$cli_bin" ${cli_opts[@]+"${cli_opts[@]}"} --extensions-dir "$dir" --list-extensions | grep -qx "$ext"; then
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

