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

ZED_DB="$HOME/.local/share/zed/db/0-stable/db.sqlite"
ZED_LOG="$HOME/.local/share/zed/logs/Zed.log"

# A booth's home is fresh, so Zed has never run here: the launch below is its
# very first, exactly what a user gets on every new booth. (The launcher may
# already have pre-created the trust table, e.g. for `zed --version` above.)
[[ ! -e "$ZED_LOG" ]] || { echo "expected a fresh home where Zed has never run"; exit 1; }

export DISPLAY="${DISPLAY:-:1}"
for _ in $(seq 1 30); do
    xwininfo -root -tree >/dev/null 2>&1 && break
    sleep 1
done

# wait_for_window <title-regex>: a Zed window whose title matches.
wait_for_window() {
    for _ in $(seq 1 60); do
        xwininfo -root -tree 2>/dev/null | grep -qiE "\"$1.*dev\.zed\.Zed" && return 0
        sleep 1
    done
    echo "no Zed window titled /$1/ appeared"
    cat /tmp/zed-launch.log || true
    tail -50 "$ZED_LOG" 2>/dev/null || true
    xwininfo -root -tree 2>/dev/null | grep -v '(has no name)' | head -40
    return 1
}

# assert_trusted <since-line>: the row is in Zed's database, and Zed restricted
# nothing in its log after <since-line>. Zed logs every worktree it restricts.
assert_trusted() {
    sleep 5   # the trust check runs once the worktree has loaded, after the window maps
    python3 - "$ZED_DB" <<'PY' || { echo "/home/coder/code is not in trusted_worktrees"; return 1; }
import sqlite3, sys
rows = sqlite3.connect(sys.argv[1]).execute(
    "SELECT 1 FROM trusted_worktrees WHERE absolute_path = '/home/coder/code' AND host_name IS NULL").fetchall()
sys.exit(0 if rows else 1)
PY
    if tail -n +"$(($1 + 1))" "$ZED_LOG" | grep -q 'is not trusted'; then
        echo "Zed opened a folder under ~/code in Restricted Mode:"
        tail -n +"$(($1 + 1))" "$ZED_LOG" | grep 'is not trusted'
        return 1
    fi
}

echo "=== First launch: Zed opens ~/code, trusted (software Vulkan) ==="
# The first five minutes of a user: click the icon, get an editor on the project.
zed >/tmp/zed-launch.log 2>&1 || true
wait_for_window 'code'
xwininfo -root -tree | grep -i 'dev.zed.Zed' | head -3
assert_trusted 0

echo "=== Relaunch on a subfolder: still trusted ==="
pkill -x zed-editor || true
for _ in $(seq 1 30); do pgrep -x zed-editor >/dev/null || break; sleep 1; done
log_mark=$(wc -l < "$ZED_LOG")
zed /home/coder/code/src >/tmp/zed-launch.log 2>&1 || true
wait_for_window 'src'
assert_trusted "$log_mark"

pkill -x zed-editor || true
echo "ok"
