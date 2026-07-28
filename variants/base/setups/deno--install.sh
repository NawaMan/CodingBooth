#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs Deno scripts/tools for the 'coder' user.
# It requires deno--setup.sh to have been run first.
# Usage: deno--install.sh [deno install args...]
# Examples:
#   deno--install.sh -A -n cowsay https://deno.land/x/cowsay/mod.ts
#   deno--install.sh -Agf jsr:@luca/flag@1
#   deno--install.sh -A npm:cowsay

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 [deno install args...]" >&2
    echo "Examples:" >&2
    echo "  $0 -A -n cowsay https://deno.land/x/cowsay/mod.ts" >&2
    echo "  $0 -Agf jsr:@luca/flag@1" >&2
    echo "  $0 -A npm:cowsay" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

if ! command -v deno &> /dev/null; then
    echo "❌ Deno is not installed. Run deno--setup.sh first." >&2
    exit 1
fi

# Deno 2 split `deno install` in two: bare form adds project dependencies, and
# installing a *command* now requires --global (permission flags are global-only).
# A Boothfile `install deno …` is always the command form — project dependencies go
# through deno-pkg--install.sh — so default to --global when the caller didn't say.
has_global=0
for arg in "$@"; do
    case "$arg" in
        --global) has_global=1; break ;;
        --*)      ;;                       # other long flag; not a short bundle
        -*g*)     has_global=1; break ;;   # short bundle carrying g, e.g. -Agf
    esac
done
[ "$has_global" -eq 0 ] && set -- --global "$@"

# Install as coder user so scripts go to ~/.deno/bin
echo "📦 Installing: deno install $*"
sudo -u coder bash -lc "deno install $*"
