#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

# The xfce template auto-selects +modern-theme (Greybird-dark/Adwaita) and
# +plank (Plank Reloaded dock), so a Boothfile-built XFCE booth gets the same
# look as the desktop-xfce variant. Both must run after `setup xfce` (they skip
# when XFCE is absent), and each can be dropped with `~`.

begin

boothfile="$prj/.booth/Boothfile"

# pass/fail line in the same format as assert-line, for checks it can't express
check() {
    local label="$1"; shift
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

line_of() { grep -n -x "$1" "$boothfile" | head -1 | cut -d: -f1; }
after_xfce() {
    local x t
    x="$(line_of 'setup xfce')"; t="$(line_of "$1")"
    [[ -n "$x" && -n "$t" && "$t" -gt "$x" ]]
}
absent() { ! grep -q "^$1" "$boothfile"; }

# --- plain xfce: both extensions come along --------------------------------
run booth config $prj --no-tui --select 'xfce'
assert-line "$boothfile" "setup xfce-theme" ""                   "xfce auto-selects +modern-theme"
assert-line "$boothfile" "setup plank" ' ${PLANK_VERSION}'       "xfce auto-selects +plank"
assert-line "$boothfile" "arg PLANK_VERSION=" ""                 "PLANK_VERSION defaults to empty (latest)"
check "setup xfce-theme runs after setup xfce" after_xfce 'setup xfce-theme'
check "setup plank runs after setup xfce"      after_xfce 'setup plank ${PLANK_VERSION}'
# xfce-theme picks defaults out of what the packs installed, so it goes after them.
after_packs() {
    local t p
    t="$(line_of 'setup xfce-theme')"
    for p in reversal-icons gruppled-cursors; do
        p="$(line_of "setup $p")"
        [[ -n "$p" && -n "$t" && "$p" -lt "$t" ]] || return 1
    done
}
check "every theme pack is installed before xfce-theme" after_packs
assert-line "$boothfile" "setup cortile" ""                      "xfce installs cortile"
check "cortile is not enabled by default" absent 'setup cortile --enable'

# --- +cortile turns it on, after it is installed ------------------------------
run booth config $prj --no-tui --overwrite --select 'xfce+cortile'
assert-line "$boothfile" "setup cortile --enable" ""             "xfce+cortile enables cortile"
after_install() {
    local i e
    i="$(line_of 'setup cortile')"; e="$(line_of 'setup cortile --enable')"
    [[ -n "$i" && -n "$e" && "$e" -gt "$i" ]]
}
check "cortile is enabled after it is installed" after_install

# --- naming an auto-selected extension with a param pins it ----------------
run booth config $prj --no-tui --overwrite --select 'xfce+plank:0.11.172-1'
assert-line "$boothfile" "arg PLANK_VERSION=" "0.11.172-1"       "xfce+plank:<ver> pins PLANK_VERSION"
run booth config $prj --no-tui --overwrite
assert-line "$boothfile" "arg PLANK_VERSION=" "0.11.172-1"       "the pin survives a reconfigure"

# --- opt-in theme templates install only, with their params wired ----------
run booth config $prj --no-tui --overwrite --select 'xfce/tela-icons/orchis-gtk/material-cursors:dark'
assert-line "$boothfile" "setup tela-icons" ' ${TELA_VERSION} ${TELA_COLOR}'                    "tela-icons installs via its setup"
assert-line "$boothfile" "setup orchis-gtk" ' ${ORCHIS_ACCENT} ${ORCHIS_SIZE} ${ORCHIS_VERSION}' "orchis-gtk installs via its setup"
assert-line "$boothfile" "arg MATERIAL_CURSORS_VARIANT=" "dark"                                 "material-cursors:dark picks the variant"

# --- Copilot is stripped from VS Code by default; this template restores it --
run booth config $prj --no-tui --overwrite --variant xfce --select 'vscode-copilot'
assert-line "$boothfile" "setup vscode-copilot" ""               "vscode-copilot restores Copilot"

# --- each can be excluded ---------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'xfce~plank'
check "xfce~plank drops setup plank"            absent 'setup plank'
assert-line "$boothfile" "setup xfce-theme" ""                   "xfce~plank keeps +modern-theme"

run booth config $prj --no-tui --overwrite --select 'xfce~modern-theme'
check "xfce~modern-theme drops setup xfce-theme" absent 'setup xfce-theme'
assert-line "$boothfile" "setup plank" ' ${PLANK_VERSION}'       "xfce~modern-theme keeps +plank"

finally
