#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: LXQt qterminal Nerd Font (Fira Code)
#
# Builds a real booth with `setup lxqt` and checks that qterminal's default
# font actually works: the Fira Code Nerd Font is installed and resolvable by
# fontconfig, and start-lxqt seeds ~/.config/qterminal.org/qterminal.ini with
# it on first run, without clobbering a later user font change.
#
# lxqt--setup.sh and fira-code-nerd-font--setup.sh are loaded from .booth/setups/
# (mirror variants/base/setups/) until the released base image ships the font.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: LXQt qterminal Nerd Font (Fira Code) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo lxqt-font-ok) || ACTUAL=""
if [[ "$ACTUAL" == "lxqt-font-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts and runs a command"
else
    print_test_result "false" "$0" "1" "booth should start and run a command"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: fontconfig actually resolves the Nerd Font (not just a file on disk).
# Not the container's very first exec'd command: a leading statement avoids a
# cold-container fontconfig race (see the XFCE terminal font test for detail).
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'echo ready; fc-match "FiraCode Nerd Font Mono"') || ACTUAL=""
if echo "$ACTUAL" | grep -qi "FiraCodeNerdFontMono"; then
    print_test_result "true" "$0" "2" "fontconfig resolves FiraCode Nerd Font Mono"
else
    print_test_result "false" "$0" "2" "fontconfig should resolve FiraCode Nerd Font Mono"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: start-lxqt seeds qterminal.ini with the Nerd Font on first run
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  nohup start-lxqt >/tmp/sl.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/qterminal.org/qterminal.ini" ] && break
    sleep 1
  done
  cat "$HOME/.config/qterminal.org/qterminal.ini" 2>&1
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^fontFamily=FiraCode Nerd Font Mono$'; then
    print_test_result "true" "$0" "3" "start-lxqt seeds qterminal.ini with the Nerd Font"
else
    print_test_result "false" "$0" "3" "start-lxqt should seed qterminal.ini with the Nerd Font"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: a pre-existing qterminal.ini (a user's own font choice) is left alone
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  mkdir -p "$HOME/.config/qterminal.org"
  printf "[General]\nfontFamily=Monospace\nfontSize=12\n" > "$HOME/.config/qterminal.org/qterminal.ini"
  nohup start-lxqt >/tmp/sl.log 2>&1 &
  sleep 6
  cat "$HOME/.config/qterminal.org/qterminal.ini"
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^fontFamily=Monospace$'; then
    print_test_result "true" "$0" "4" "an existing qterminal.ini is not overwritten"
else
    print_test_result "false" "$0" "4" "an existing qterminal.ini should not be overwritten"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: qterminal, launched the way the LXQt session actually launches it
# (an autostart entry, same as a panel/menu click), spawns bash — not the
# /bin/sh fallback it uses when $SHELL isn't set inside the dbus session.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  mkdir -p "$HOME/.config/autostart"
  cat > "$HOME/.config/autostart/test-qterminal-shell.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Test QTerminal Shell
Exec=sh -c "qterminal >/tmp/qt-shell-check.log 2>&1"
OnlyShowIn=LXQt;
DESK
  nohup start-lxqt >/tmp/sl.log 2>&1 &
  for _ in $(seq 1 20); do
    pgrep -x qterminal >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 2
  QPID=$(pgrep -x qterminal | head -1)
  [ -n "$QPID" ] && ps --ppid "$QPID" -o comm= || true
  cat /tmp/qt-shell-check.log 2>&1
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^bash$' && ! echo "$ACTUAL" | grep -qi "Fallback to"; then
    print_test_result "true" "$0" "5" "qterminal spawns bash, not the /bin/sh fallback"
else
    print_test_result "false" "$0" "5" "qterminal should spawn bash, not the /bin/sh fallback"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
