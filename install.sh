#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# CodingBooth Installer
# Usage: curl -fsSL https://codingbooth.io/install.sh | bash

set -euo pipefail

# Report whether this machine can run a booth. Never aborts the install —
# the wrapper and binary are still useful without Docker — but Linux
# rootless / userns-remap will refuse at `booth` unless --rootless is passed.
check_host_requirements() {
    echo ""
    echo "Checking host requirements..."

    if ! command -v bash >/dev/null 2>&1; then
        echo "  bash:  missing (needed for the booth wrapper)"
    else
        echo "  bash:  ok"
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "  curl:  missing (needed to install and update)"
    else
        echo "  curl:  ok"
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "  docker: not found on PATH"
        echo ""
        echo "Warning: CodingBooth is installed, but you cannot start a booth until Docker is available."
        echo "  Linux:        Docker Engine, rootful (your user can run: docker info)"
        echo "  macOS/Windows: Docker Desktop (standard install)"
        echo "Linux rootless Docker and userns-remap are not supported."
        return 0
    fi

    local errfile info_json
    errfile=$(mktemp)
    if ! info_json=$(docker info --format '{{json .SecurityOptions}}' 2>"$errfile"); then
        local err
        err=$(tr -d '\r' <"$errfile")
        rm -f "$errfile"
        echo "  docker: installed, but this user cannot talk to the daemon"
        echo ""
        if echo "$err" | grep -qi 'permission denied'; then
            echo "Warning: permission denied talking to Docker."
            echo "  On Linux:  sudo usermod -aG docker \$USER"
            echo "  Then log out and back in. Confirm with: docker info"
        else
            echo "Warning: Docker is installed but the daemon is not running (or not reachable)."
            echo "  Start Docker Desktop, or on Linux: sudo service docker start"
            echo "  Confirm with: docker info"
        fi
        return 0
    fi
    rm -f "$errfile"

    echo "  docker: ok ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo daemon reachable))"

    case "$(uname -s)" in
        Linux*)
            if echo "$info_json" | grep -q 'rootless'; then
                echo ""
                echo "Warning: this machine looks like Linux rootless Docker."
                echo "CodingBooth cannot create a separate coder user under rootless (host files"
                echo "appear as root inside the container). macOS/Windows Docker Desktop and Linux"
                echo "rootful Docker work. \`booth\` will refuse to start."
                echo "To try anyway (unsupported): booth --rootless"
            elif echo "$info_json" | grep -q 'name=userns'; then
                echo ""
                echo "Warning: this machine looks like Linux Docker with userns-remap."
                echo "CodingBooth cannot create a separate coder user in that mode."
                echo "\`booth\` will refuse to start. To try anyway (unsupported): booth --rootless"
            fi
            ;;
    esac
}

install_codingbooth() {
    # Download (don't pipe-bash) the wrapper. Piping would trigger the wrapper's
    # own pipe-install branch, which delegates back to this script — infinite loop.
    curl -fsSL -o booth https://github.com/NawaMan/CodingBooth/releases/download/latest/booth
    chmod +x booth
    ./booth install
    ./booth shell-config install

    echo ""
    echo "Restart your shell (or open a new terminal) to use 'booth' from anywhere."
    echo "Until then, use ./booth from this directory."

    check_host_requirements
}

if [[ "${1:-}" == "--check-only" ]]; then
    check_host_requirements
    exit 0
fi

install_codingbooth
