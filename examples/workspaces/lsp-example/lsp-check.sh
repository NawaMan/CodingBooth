#!/bin/bash
# Starts each language server this booth installs and sends it an LSP
# `initialize`, the first request every editor makes. A server that answers
# with its capabilities is one Fresh, Helix, and Neovim can use.
set -uo pipefail

ROOT="file://$(pwd)"
REQUEST="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":\"${ROOT}\",\"capabilities\":{}}}"

failed=0
check() {
    local label="$1"; shift
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "✘ ${label}: $1 is not installed"
        failed=1
        return
    fi
    local reply
    reply=$( (printf 'Content-Length: %d\r\n\r\n%s' "${#REQUEST}" "$REQUEST"; sleep 5) \
             | timeout 15 "$@" 2>/dev/null | head -c 4000)
    if grep -q '"capabilities"' <<< "$reply"; then
        echo "✓ ${label}: $*"
    else
        echo "✘ ${label}: $* did not answer initialize"
        failed=1
    fi
}

check "Markdown"   marksman server
check "TOML"       taplo lsp stdio
check "YAML"       yaml-language-server --stdio
check "Bash"       bash-language-server start
check "TypeScript" typescript-language-server --stdio

exit "$failed"
