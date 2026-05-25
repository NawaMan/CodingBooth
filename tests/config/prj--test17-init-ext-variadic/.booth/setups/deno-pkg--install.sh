#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Usage: $0 <pkg1,pkg2,...>" >&2
    exit 1
fi

if ! command -v deno &> /dev/null; then
    echo "❌ Deno is not installed. Run deno--setup.sh first." >&2
    exit 1
fi

IFS=',' read -ra PKGS <<< "$1"
for pkg in "${PKGS[@]}"; do
    pkg=$(echo "$pkg" | xargs)
    if [ -n "$pkg" ]; then
        echo "📦 Installing: deno add $pkg"
        sudo -u coder bash -lc "cd /home/coder && deno add $pkg"
    fi
done
