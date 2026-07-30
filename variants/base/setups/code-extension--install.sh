#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs arbitrary VS Code / code-server extensions by marketplace id.
# It is the escape hatch beside the curated `<lang>-code-extension--setup.sh` scripts:
# those pin a known-good id per language, this one takes whatever you name.
#
# Usage: code-extension--install.sh <publisher.name>[@<version>] [more...]
# Example: code-extension--install.sh elixir-lsp.elixir-ls
#          code-extension--install.sh elixir-lsp.elixir-ls ms-python.python
#          code-extension--install.sh eamodio.gitlens@15.6.0
#
# Ids resolve against Open VSX (https://open-vsx.org), the registry code-server
# queries -- NOT the Microsoft Marketplace. The same extension often carries a
# different publisher on each (ElixirLS is `elixir-lsp.elixir-ls` on Open VSX and
# `JakeBecker.elixir-ls` on the Marketplace), and Microsoft-licensed extensions
# (ms-dotnettools.*, ms-vscode.cpptools, ...) are not on Open VSX at all. Look the
# id up at https://open-vsx.org before adding it here.
#
# Reproducibility: a trailing `@version` pins the extension to that release and is
# passed straight through to `--install-extension`. Without it you get whatever is
# latest at build time. See docs/REPRODUCIBILITY.md.
#
# Unlike the curated per-language setups, a failed or unresolvable id is a hard
# error here: you named it explicitly, so a silent no-op would hand you an image
# that is missing the extension you asked for.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Usage: $0 <publisher.name>[@<version>] [more...]" >&2
    echo "Example: $0 elixir-lsp.elixir-ls" >&2
    echo "         $0 elixir-lsp.elixir-ls ms-python.python" >&2
    exit 1
fi

# This script always runs as root during the build.
HOME=/root

# Expand comma-separated ids into separate arguments.
set -- $(echo "$@" | tr ',' ' ')

SETUP_DIR="$(dirname "$0")"
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
CODE_EXTENSION_LIB=${CODE_EXTENSION_LIB:-code-extension-source.sh}
# Reuse the extension-dir / cli-binary resolution the curated setups use, so both
# paths install into the same shared dirs. Only the failure handling differs.
source "${SETUP_LIBS_DIR}/${CODE_EXTENSION_LIB}"

if ! "${SETUP_DIR}/cb-has-vscode.sh"; then
    echo "❌ Neither code-server nor VS Code is installed in this image." >&2
    echo "   \`install code-extension\` needs an editor to install into. Add the" >&2
    echo "   codeserver template (\`setup codeserver\`) or build on the codeserver" >&2
    echo "   variant, then retry." >&2
    exit 1
fi

# Under QEMU emulation (arm64 cross-build on amd64) code-server's bundled Node
# fails with "Invalid ELF image", so nothing can be installed or verified here.
# Skip rather than fail: the build host, not the requested ids, is the blocker.
if is_qemu; then
    echo "⚠️  QEMU detected — cannot install extensions during a cross-build; skipping." >&2
    for ext in "$@"; do echo "   skipped: ${ext}" >&2; done
    exit 0
fi

CLIS=()
command -v code        >/dev/null 2>&1 && CLIS+=("code")
command -v code-server >/dev/null 2>&1 && CLIS+=("code-server")

FAILED=()

for cli in "${CLIS[@]}"; do
    DIR="$(ext_dir_for_cli "$cli")"
    CLI_BIN="$(cli_bin_for_install "$cli")"
    CLI_OPTS=()

    mkdir -p "$DIR"

    if [ "$cli" = "code" ] && [ "$EUID" -eq 0 ]; then
        VSCODE_ROOT_DATA="/tmp/vscode-root-user-data"
        mkdir -p "$VSCODE_ROOT_DATA"
        CLI_OPTS=(--no-sandbox --user-data-dir "$VSCODE_ROOT_DATA")
    fi

    echo "🧩 Installing extensions via ${CLI_BIN} (extensions dir: ${DIR}) ..."
    for ext in "$@"; do
        [ -n "$ext" ] || continue

        if ! "$CLI_BIN" "${CLI_OPTS[@]}" --extensions-dir "$DIR" --install-extension "$ext"; then
            echo "  ❌ Failed to install: ${ext} (via ${cli})" >&2
            FAILED+=("${ext} (${cli})")
            continue
        fi

        # `--install-extension` can report success for an id that never landed, so
        # confirm against the installed list. The list carries no @version suffix.
        ext_id="${ext%@*}"
        if "$CLI_BIN" "${CLI_OPTS[@]}" --extensions-dir "$DIR" --list-extensions \
            | grep -qix "$ext_id"; then
            echo "  ✔ ${ext}"
        else
            echo "  ❌ Not found after install: ${ext} (via ${cli})" >&2
            FAILED+=("${ext} (${cli})")
        fi
    done

    # Some extensions write runtime files inside their own extension folder, which
    # the non-root runtime user (coder) must be able to do.
    find "$DIR" -type d -exec chmod a+w {} +
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "" >&2
    echo "❌ ${#FAILED[@]} extension(s) failed to install:" >&2
    for f in "${FAILED[@]}"; do echo "   - ${f}" >&2; done
    echo "" >&2
    echo "   Check the id at https://open-vsx.org — code-server resolves against" >&2
    echo "   Open VSX, not the Microsoft Marketplace, and publisher names differ." >&2
    exit 1
fi

echo "✅ Extension installation completed."
