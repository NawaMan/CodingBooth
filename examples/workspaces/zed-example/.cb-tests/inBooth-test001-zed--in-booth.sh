#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

echo "=== Zed version ==="
ver="$(zed --version 2>&1 || true)"
echo "$ver" | grep -q "1.25.3" || { echo "expected 1.25.3, got: $ver"; exit 1; }

echo "=== Desktop entry points at the launcher ==="
grep -q '^Exec=/usr/local/bin/zed' /usr/share/applications/dev.zed.Zed.desktop \
    || { echo "dev.zed.Zed.desktop does not launch /usr/local/bin/zed"; exit 1; }

echo "=== Self-updater is off (the booth pins the version) ==="
grep -q '"auto_update": false' "$HOME/.config/zed/settings.json" \
    || { echo "~/.config/zed/settings.json does not turn auto_update off"; exit 1; }

echo "=== Zed opens a window on the desktop (software Vulkan) ==="
# The first five minutes of a user: click the icon, get an editor window on the project.
export DISPLAY="${DISPLAY:-:1}"
for _ in $(seq 1 30); do
    xwininfo -root -tree >/dev/null 2>&1 && break
    sleep 1
done
zed /home/coder/code/src/hello.py >/tmp/zed-launch.log 2>&1 || true

found=""
for _ in $(seq 1 60); do
    if xwininfo -root -tree 2>/dev/null | grep -qiE 'dev\.zed\.Zed'; then
        found=yes
        break
    fi
    sleep 1
done
if [[ -z "$found" ]]; then
    echo "no Zed window appeared"
    cat /tmp/zed-launch.log || true
    tail -50 "$HOME/.local/share/zed/logs/Zed.log" 2>/dev/null || true
    xwininfo -root -tree 2>/dev/null | grep -v '(has no name)' | head -40
    exit 1
fi
xwininfo -root -tree | grep -i 'zed' | head -3
pkill -f zed-editor || true
echo "ok"
