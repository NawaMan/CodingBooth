#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb-plank-start
#
# Runs the real dock starter against a fake applications dir and desktop-icon
# registry, with gsettings stubbed by a file that keeps dock-items between runs
# (as dconf does) and plank stubbed to a no-op.
#
# Locked in here:
#   - the first session seeds the defaults, then every desktop-icon app after
#   - a launcher that is both a default and a desktop icon appears once
#   - a web-service icon (only in the registry's apps dir copy) is docked too
#   - an app added to the registry later is appended to the existing dock
#   - an app the user took off the dock is not put back
#   - a home seeded before desktop icons were docked gets them added once
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_CMD="$REPO_ROOT/variants/base/setups/cb-plank-start"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/home" "$STUB/apps" "$STUB/skel"
ITEMS="$STUB/dock-items"

# ---- fake applications dir and registry ----
for a in xfce4-terminal thunar google-chrome firefox com.microsoft.VSCode texstudio viewmd-web; do
  printf '[Desktop Entry]\nName=%s\nExec=%s\n' "$a" "$a" > "$STUB/apps/$a.desktop"
done
# The registry copy of a launcher that exists only there (a project's own).
printf '[Desktop Entry]\nName=Mine\nExec=mine\n' > "$STUB/skel/mine.desktop"
for a in com.microsoft.VSCode firefox google-chrome texstudio viewmd-web; do
  cp "$STUB/apps/$a.desktop" "$STUB/skel/"
done

# ---- stubs ----
# gsettings: dock-items lives in a file, so a later run reads what the last set.
cat > "$STUB/bin/gsettings" << EOF
#!/bin/bash
case "\$1 \$3" in
  "get dock-items") [ -s "$ITEMS" ] && cat "$ITEMS" || echo "@as []" ;;
  "set dock-items") echo "\$4" > "$ITEMS" ;;
esac
EOF
chmod +x "$STUB/bin/"*

run() {
  env HOME="$STUB/home" PATH="$STUB/bin:$PATH" APPS_DIR="$STUB/apps" \
      SKEL_DESKTOP="$STUB/skel" PLANK_BIN=true bash "$START_CMD" 2>&1
}

ALL_PASSED=true
TEST_NUM=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = "true" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [ -n "$detail" ] && echo "$detail" | sed 's/^/          /'
        ALL_PASSED=false
    fi
}
is() { [ "$1" = "$2" ] && echo true || echo false; }
LAUNCHERS="$STUB/home/.config/plank/dock1/launchers"

# --- first session ---------------------------------------------------------------
run >/dev/null
check "first session: defaults, then desktop-icon apps, each once" \
  "$(is "$(cat "$ITEMS")" "['xfce4-terminal.dockitem', 'thunar.dockitem', 'google-chrome.dockitem', 'firefox.dockitem', 'com.microsoft.VSCode.dockitem', 'mine.dockitem', 'texstudio.dockitem', 'viewmd-web.dockitem']")" \
  "$(cat "$ITEMS")"
check "an app's launcher points at the applications dir" \
  "$(is "$(sed -n 's/^Launcher=//p' "$LAUNCHERS/texstudio.dockitem")" "file://$STUB/apps/texstudio.desktop")"
check "a registry-only launcher points at the registry copy" \
  "$(is "$(sed -n 's/^Launcher=//p' "$LAUNCHERS/mine.dockitem")" "file://$STUB/skel/mine.desktop")"

# --- the user takes an app off, then the image gains a new one -------------------
echo "['xfce4-terminal.dockitem', 'firefox.dockitem', 'texstudio.dockitem']" > "$ITEMS"
cp "$STUB/apps/thunar.desktop" "$STUB/apps/gimp.desktop"
cp "$STUB/apps/gimp.desktop" "$STUB/skel/"
run >/dev/null
check "a new app is appended; removed ones stay off" \
  "$(is "$(cat "$ITEMS")" "['xfce4-terminal.dockitem', 'firefox.dockitem', 'texstudio.dockitem', 'gimp.dockitem']")" \
  "$(cat "$ITEMS")"

# --- nothing new: the dock is left alone -----------------------------------------
echo "['firefox.dockitem']" > "$ITEMS"
run >/dev/null
check "a restart with no new apps changes nothing" "$(is "$(cat "$ITEMS")" "['firefox.dockitem']")" "$(cat "$ITEMS")"

# --- a home seeded by the earlier starter (marker, no offered list) --------------
rm -f "$STUB/home/.config/plank/dock1/.cb-offered"
echo "['xfce4-terminal.dockitem', 'thunar.dockitem', 'google-chrome.dockitem', 'firefox.dockitem']" > "$ITEMS"
run >/dev/null
check "an older home gets desktop-icon apps once, not removed defaults" \
  "$(is "$(cat "$ITEMS")" "['xfce4-terminal.dockitem', 'thunar.dockitem', 'google-chrome.dockitem', 'firefox.dockitem', 'gimp.dockitem', 'mine.dockitem', 'texstudio.dockitem', 'viewmd-web.dockitem']")" \
  "$(cat "$ITEMS")"

if [ "$ALL_PASSED" != "true" ]; then
    exit 1
fi
