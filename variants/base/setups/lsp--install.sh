#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

# Installs language servers by name, each through its own lsp--<name>--setup.sh.
# Usage: lsp--install.sh <name[@version]> [name[@version]...]
# Example: lsp--install.sh marksman taplo@0.10.0 yaml
#
# A name is a server (marksman, taplo, pylsp, ...) or the language it serves
# (markdown, toml, python, ...). Comma-separated lists work too, because the lsp
# template passes its variadic LSP_SERVERS as one value.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

# Every lsp--<name>--setup.sh next to this script or on PATH is installable.
available() {
    {
        ls "$(dirname "$0")" 2>/dev/null || true
        local d
        for d in ${PATH//:/ }; do ls "$d" 2>/dev/null || true; done
    } | sed -n 's/^lsp--\(.*\)--setup\.sh$/\1/p' | sort -u
}

case "${1:-}" in
    -h|--help|--list)
        echo "Usage: $0 <name[@version]> [name[@version]...]"
        echo "Installs language servers. No names is a no-op."
        echo
        echo "Servers:   $(available | tr '\n' ' ')"
        echo "Languages: markdown toml terraform sql json html css javascript react tailwind python c cpp java haskell zig"
        exit 0
        ;;
esac

# Expand comma-separated names into separate arguments.
set -- $(echo "$@" | tr ',' ' ')

# The lsp template always emits `install lsp ${LSP_SERVERS}`, empty unless the
# user typed names, so no names must build cleanly.
if [ $# -eq 0 ]; then
    echo "ℹ️  No language servers requested; nothing to install."
    exit 0
fi

for spec in "$@"; do
    name="${spec%%@*}"
    version=""
    [[ "$spec" == *@* ]] && version="${spec#*@}"

    # A language name resolves to the server that the editors start for it.
    case "$name" in
        markdown|md)            name="marksman" ;;
        toml)                   name="taplo" ;;
        terraform|tf|hcl)       name="terraform-ls" ;;
        sql)                    name="sqls" ;;
        json|jsonc|html|css)    name="vscode-langservers" ;;
        javascript|js|ts)       name="typescript" ;;
        tailwind)               name="tailwindcss" ;;
        python|py)              name="pylsp" ;;
        compose)                name="docker-compose" ;;
        shell|sh)               name="bash" ;;
        c|cpp|c++|cxx)          name="clangd" ;;
        java)                   name="jdtls" ;;
        react|jsx|tsx)          name="typescript" ;;
        haskell|hs)             name="hls" ;;
        zig)                    name="zls" ;;
    esac

    script="lsp--${name}--setup.sh"
    if [ -x "$(dirname "$0")/${script}" ]; then
        script="$(dirname "$0")/${script}"
    elif ! command -v "$script" >/dev/null 2>&1; then
        echo "❌ Unknown language server: '${spec}'" >&2
        echo "   Servers: $(available | tr '\n' ' ')" >&2
        exit 1
    fi

    if [ -n "$version" ]; then
        "$script" --version "$version"
    else
        "$script"
    fi
done
