#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: booth--theme
#
# Runs the real command against a fake theme tree with the desktop's tools
# stubbed (pgrep, xfconf-query, gsettings), and asserts the exact calls it makes.
#
# Locked in here:
#   - each type writes the property XFCE's own Settings writes (a wrong channel
#     or path "succeeds" silently and changes nothing on screen)
#   - set validates against what is installed, and refuses before writing
#   - cursor-only themes are not offered as icon themes
#   - reset removes the user value (-r) instead of writing the default back
#   - non-XFCE desktops and no desktop fail clearly rather than guessing
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME_CMD="$REPO_ROOT/variants/base/setups/booth--theme"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/home" "$STUB/share"
CALLS="$STUB/calls.txt"

# ---- fake theme tree ----
S="$STUB/share"
mkdir -p "$S/themes/Greybird-dark/gtk-3.0" "$S/themes/Orchis-Dark/gtk-3.0" \
         "$S/themes/Orchis-Dark/xfwm4"  "$S/themes/Default/xfwm4"
mkdir -p "$S/icons/Reversal-dark/scalable" "$S/icons/gruppled_white/cursors" \
         "$S/icons/Adwaita/cursors"
printf '[Icon Theme]\nName=Reversal-dark\nDirectories=scalable\n' > "$S/icons/Reversal-dark/index.theme"
printf '[Icon Theme]\nName=Gruppled White\n'                     > "$S/icons/gruppled_white/index.theme"
printf '[Icon Theme]\nName=Adwaita\nDirectories=16x16\n'         > "$S/icons/Adwaita/index.theme"
mkdir -p "$S/plank/themes/Matte" "$S/plank/themes/Default"

# ---- stubs ----
# pgrep: the running "desktop" is whatever $FAKE_DESKTOP names.
cat > "$STUB/bin/pgrep" << 'EOF'
#!/bin/bash
proc="${@: -1}"
[[ "$proc" == "${FAKE_DESKTOP:-}" ]] && { echo 4242; exit 0; }
exit 1
EOF
# xfconf-query / gsettings: log every call; answer reads with fixed values.
cat > "$STUB/bin/xfconf-query" << EOF
#!/bin/bash
echo "xfconf-query \$*" >> "$CALLS"
case "\$*" in
  *" -s "*|*" -r"*) exit 0 ;;
  *IconThemeName*) echo Reversal-dark ;;
  *ThemeName*)     echo Greybird-dark ;;
  *general/theme*) echo Orchis-Dark ;;
  *CursorThemeName*) echo gruppled_white ;;
  *CursorThemeSize*) echo 40 ;;
esac
EOF
cat > "$STUB/bin/gsettings" << EOF
#!/bin/bash
echo "gsettings \$*" >> "$CALLS"
case "\$1" in
  list-keys) [[ -z "\${NO_PLANK:-}" ]] || exit 1; echo theme; echo hide-mode ;;
  range)     printf "enum\n'none'\n'intelligent'\n'auto'\n" ;;
  get)       [[ "\$3" == theme ]] && echo "'Matte'" || echo "'none'" ;;
esac
EOF
chmod +x "$STUB/bin/"*

# Session already attached, so no /proc lookup; theme tree points at the fake.
run() {
  env HOME="$STUB/home" PATH="$STUB/bin:$PATH" BOOTH_THEME_SHARE_DIR="$S" \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/fake DISPLAY=:1 FAKE_DESKTOP="${FAKE_DESKTOP-xfce4-session}" \
      NO_PLANK="${NO_PLANK:-}" bash "$THEME_CMD" "$@" 2>&1
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
has() { grep -qxF -- "$2" <<< "$1" && echo true || echo false; }

# --- set writes where XFCE Settings writes -----------------------------------
expect_set() {   # expect_set <type> <value> <expected call>
  : > "$CALLS"
  local out rc
  out=$(run set "$1" "$2") && rc=0 || rc=$?
  check "set $1 $2 → $3" "$( [ $rc -eq 0 ] && has "$(cat "$CALLS")" "$3" )" "rc=$rc out=$out calls: $(cat "$CALLS")"
}
expect_set gtk         Greybird-dark    "xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Greybird-dark"
expect_set wm          Orchis-Dark  "xfconf-query -c xfwm4 -p /general/theme -n -t string -s Orchis-Dark"
expect_set icons       Reversal-dark    "xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s Reversal-dark"
expect_set cursor      gruppled_white   "xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s gruppled_white"
expect_set cursor-size 40               "xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 40"
expect_set dock        Matte            "gsettings set net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/ theme Matte"
expect_set dock-hide   intelligent      "gsettings set net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/ hide-mode intelligent"

# --- validation refuses before writing ---------------------------------------
refuses() {   # refuses <desc> <args...>
  local desc="$1"; shift
  : > "$CALLS"
  local out rc
  out=$(run "$@") && rc=0 || rc=$?
  check "$desc" "$( [ $rc -ne 0 ] && ! grep -qE ' -s |gsettings set' "$CALLS" && echo true || echo false )" "rc=$rc out=$out calls: $(cat "$CALLS")"
}
refuses "an uninstalled theme is refused"          set gtk No-Such-Theme
refuses "a gtk-only theme is not a wm theme"       set wm Greybird-dark
refuses "a cursor-only theme is not an icon theme" set icons gruppled_white
refuses "a non-numeric cursor-size is refused"     set cursor-size big
refuses "an unknown type is refused"               set colour red
refuses "a hide mode outside the schema is refused" set dock-hide sometimes
NO_PLANK=1 refuses "dock types need Plank"         set dock Matte

# --- list ----------------------------------------------------------------------
OUT=$(run list icons)
check "list icons marks the current one"      "$(has "$OUT" "* Reversal-dark")" "$OUT"
check "list icons offers other icon themes"   "$(has "$OUT" "  Adwaita")" "$OUT"
check "list icons leaves cursor-only themes out" "$( ! grep -q gruppled <<< "$OUT" && echo true || echo false )" "$OUT"
OUT=$(run list wm)
check "list wm offers only xfwm4 themes" "$(is "$OUT" "$(printf '  Default\n* Orchis-Dark')")" "$OUT"

# --- show / reset ---------------------------------------------------------------
OUT=$(run)
check "show prints every type" "$(has "$OUT" "dock-hide    none")" "$OUT"
: > "$CALLS"; run reset icons >/dev/null
check "reset removes the user value" "$(has "$(cat "$CALLS")" "xfconf-query -c xsettings -p /Net/IconThemeName -r")" "$(cat "$CALLS")"

# --- other desktops -------------------------------------------------------------
OUT=$(FAKE_DESKTOP=plasmashell run) && RC=0 || RC=$?
check "KDE says not supported yet" "$( [ $RC -ne 0 ] && grep -q 'kde desktop is not supported yet' <<< "$OUT" && echo true || echo false )" "$OUT"
OUT=$(FAKE_DESKTOP= run) && RC=0 || RC=$?
check "no desktop says so" "$( [ $RC -ne 0 ] && grep -q 'no desktop is running' <<< "$OUT" && echo true || echo false )" "$OUT"

if [ "$ALL_PASSED" != "true" ]; then
    exit 1
fi
