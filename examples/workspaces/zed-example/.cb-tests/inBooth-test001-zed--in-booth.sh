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

echo "=== ~/code is trusted on the next launch (no Restricted Mode) ==="
# The first run creates Zed's database; quit, and the launcher adds the trust
# row before the next start.
ZED_DB="$HOME/.local/share/zed/db/0-stable/db.sqlite"
ZED_LOG="$HOME/.local/share/zed/logs/Zed.log"
for _ in $(seq 1 30); do [[ -f "$ZED_DB" ]] && break; sleep 1; done
pkill -x zed-editor || true
for _ in $(seq 1 30); do pgrep -x zed-editor >/dev/null || break; sleep 1; done

log_mark=$(wc -l < "$ZED_LOG")
zed /home/coder/code/src >/tmp/zed-launch.log 2>&1 || true

python3 - "$ZED_DB" <<'PY' || { echo "/home/coder/code is not in trusted_worktrees"; exit 1; }
import sqlite3, sys
rows = sqlite3.connect(sys.argv[1]).execute(
    "SELECT 1 FROM trusted_worktrees WHERE absolute_path = '/home/coder/code' AND host_name IS NULL").fetchall()
sys.exit(0 if rows else 1)
PY

# Zed logs every worktree it restricts; a subfolder of ~/code must not be one.
for _ in $(seq 1 60); do
    xwininfo -root -tree 2>/dev/null | grep -qiE '"src.*dev\.zed\.Zed' && break
    sleep 1
done
sleep 5   # the trust check runs once the worktree has loaded, after the window maps
if tail -n +"$((log_mark + 1))" "$ZED_LOG" | grep -q 'is not trusted'; then
    echo "Zed still restricted a folder under ~/code:"
    tail -n +"$((log_mark + 1))" "$ZED_LOG" | grep 'is not trusted'
    exit 1
fi
xwininfo -root -tree 2>/dev/null | grep -qiE '"src.*dev\.zed\.Zed' \
    || { echo "Zed did not reopen on ~/code/src"; exit 1; }

pkill -x zed-editor || true
echo "ok"
