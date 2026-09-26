#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the i3 setups inside real XFCE and LXQt images
#
# Runs the repo's i3--setup.sh and its three extension setups (i3-default,
# i3-ctrl-alt, i3-gaps) in throwaway containers of the desktop images — the
# setups are mounted in, so the image only has to carry the desktop — and
# asserts what they leave behind. No booth and no session is started; that
# half (i3 at login, stop-i3 / start-i3 live) is the i3-desktop-example test.
#
# Images: CB_XFCE_IMAGE / CB_LXQT_IMAGE (default: the -latest desktop images).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
XFCE_IMAGE="${CB_XFCE_IMAGE:-nawaman/codingbooth:desktop-xfce-latest}"
LXQT_IMAGE="${CB_LXQT_IMAGE:-nawaman/codingbooth:desktop-lxqt-latest}"

echo "=== Test: i3 setups inside real XFCE and LXQt images ==="

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

MOUNTS=()
for s in i3 i3-default i3-ctrl-alt i3-gaps; do
    MOUNTS+=(-v "$SETUPS/$s--setup.sh:/opt/codingbooth/setups/$s--setup.sh:ro")
done

# in_image <image> <script> — run the setups, then <script>; prints its output.
in_image() {
    docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null
    docker run --rm "${MOUNTS[@]}" --entrypoint bash "$1" -c "
        export PATH=/opt/codingbooth/setups:\$PATH
        $2" < /dev/null 2>&1
}

# has <output> <line> — the output contains exactly that line.
has() { grep -qxF -- "$2" <<< "$1"; }

# One report per desktop, as KEY=value lines, so every assertion reads one run.
REPORT='
    for s in i3 i3-default i3-ctrl-alt i3-gaps; do
        $s--setup.sh >/tmp/$s.log 2>&1 && echo "$s=ok" || { echo "$s=FAILED"; tail -5 /tmp/$s.log; }
    done
    i3 -C -c /etc/xdg/i3/config >/dev/null 2>&1 && echo "config=valid"
    i3 -C -c /etc/i3/config     >/dev/null 2>&1 && echo "etc-config=valid"
    grep -qx "include /etc/xdg/i3/config" /etc/i3/config && echo "etc-config=includes-ours"
    grep -q i3-config-wizard /etc/i3/config && echo "etc-config=wizard"
    echo "twins=$(grep -c "^bindsym Control+Mod1+" /etc/xdg/i3/config.d/ctrl-alt.conf)"
    echo "mod-bindings=$(grep -c "^bindsym \$mod+" /etc/xdg/i3/config)"
    grep -qx "gaps inner 8" /etc/xdg/i3/config.d/gaps.conf && echo "gaps=8"
    for c in start-i3 stop-i3 cb-i3-wallpaper cb-i3-dock; do [ -x /usr/local/bin/$c ] && echo "cmd=$c"; done
    [ -f /etc/skel/Desktop/cb-i3-start.desktop ] && echo "desktop-icon=yes"
    [ -f /usr/share/icons/hicolor/scalable/apps/cb-i3.svg ] && echo "icon=yes"
    ls /usr/local/share/booth-message-wrapper/plugins/ 2>/dev/null | sed "s/^/plugin=/"
    i3-gaps--setup.sh wide >/dev/null 2>&1 || echo "bad-gap=rejected"
'

# ---- XFCE ----
OUT=$(in_image "$XFCE_IMAGE" "$REPORT"'
    X=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
    grep -q "value=\"i3\"" $X/xfce4-session.xml && echo "session=i3"
    grep -qE "value=\"(xfwm4|xfdesktop)\"" $X/xfce4-session.xml && echo "session=still-xfwm4-or-xfdesktop"
    grep -q "name=\"Count\" type=\"int\" value=\"4\"" $X/xfce4-session.xml && echo "session-count=4"
    for a in xfce-set-wallpaper cb-xfce-arrange-icons; do grep -qx Hidden=true /etc/xdg/autostart/$a.desktop && echo "hidden=$a"; done
    echo "xfce-clashes=$(grep -c "&lt;Primary&gt;&lt;Alt&gt;[lf]\"" $X/xfce4-keyboard-shortcuts.xml)"
    grep -q "exo-open --launch TerminalEmulator" /etc/xdg/i3/config && echo "terminal=exo-open"
    grep -q "^DESKTOP=xfce$" /usr/local/bin/start-i3 && echo "start-i3=xfce"
')
for s in i3 i3-default i3-ctrl-alt i3-gaps; do
    has "$OUT" "$s=ok" && check "true" "XFCE: $s--setup.sh succeeds" || check "false" "XFCE: $s--setup.sh succeeds" "$OUT"
done
has "$OUT" "config=valid" && has "$OUT" "etc-config=valid" \
    && check "true" "XFCE: i3 accepts both config entry points" || check "false" "XFCE: i3 accepts both config entry points" "$OUT"
has "$OUT" "etc-config=includes-ours" && ! has "$OUT" "etc-config=wizard" \
    && check "true" "XFCE: /etc/i3/config includes ours, no first-run wizard" || check "false" "XFCE: /etc/i3/config includes ours, no first-run wizard" "$OUT"
MODS=$(sed -n 's/^mod-bindings=//p' <<< "$OUT"); TWINS=$(sed -n 's/^twins=//p' <<< "$OUT")
[[ -n "$MODS" && "$MODS" -gt 40 && "$MODS" == "$TWINS" ]] \
    && check "true" "XFCE: a Ctrl+Alt twin for every mod binding ($TWINS)" || check "false" "XFCE: a Ctrl+Alt twin for every mod binding" "mod=$MODS twins=$TWINS"
has "$OUT" "gaps=8" && has "$OUT" "bad-gap=rejected" \
    && check "true" "XFCE: 8px gaps; a non-numeric gap is rejected" || check "false" "XFCE: 8px gaps; a non-numeric gap is rejected" "$OUT"
has "$OUT" "cmd=start-i3" && has "$OUT" "cmd=stop-i3" && has "$OUT" "cmd=cb-i3-wallpaper" && has "$OUT" "cmd=cb-i3-dock" && has "$OUT" "start-i3=xfce" \
    && check "true" "XFCE: start-i3 / stop-i3 and helpers installed for XFCE" || check "false" "XFCE: start-i3 / stop-i3 and helpers installed for XFCE" "$OUT"
has "$OUT" "desktop-icon=yes" && has "$OUT" "icon=yes" \
    && check "true" "XFCE: desktop icon with its own icon" || check "false" "XFCE: desktop icon with its own icon" "$OUT"
has "$OUT" "plugin=i3-00-ctrl-alt.js" && has "$OUT" "plugin=i3-help.js" \
    && check "true" "XFCE: Help plugins, Ctrl+Alt flag first" || check "false" "XFCE: Help plugins, Ctrl+Alt flag first" "$OUT"
has "$OUT" "session=i3" && has "$OUT" "session-count=4" && ! has "$OUT" "session=still-xfwm4-or-xfdesktop" \
    && check "true" "XFCE: session logs in on i3, without xfwm4 or xfdesktop" || check "false" "XFCE: session logs in on i3, without xfwm4 or xfdesktop" "$OUT"
has "$OUT" "hidden=xfce-set-wallpaper" && has "$OUT" "hidden=cb-xfce-arrange-icons" \
    && check "true" "XFCE: xfdesktop-starting autostarts hidden" || check "false" "XFCE: xfdesktop-starting autostarts hidden" "$OUT"
has "$OUT" "xfce-clashes=0" \
    && check "true" "XFCE: Ctrl+Alt+l / Ctrl+Alt+f shortcuts dropped" || check "false" "XFCE: Ctrl+Alt+l / Ctrl+Alt+f shortcuts dropped" "$OUT"
has "$OUT" "terminal=exo-open" \
    && check "true" "XFCE: mod+Enter opens the preferred terminal" || check "false" "XFCE: mod+Enter opens the preferred terminal" "$OUT"

# ---- LXQt ----
OUT=$(in_image "$LXQT_IMAGE" "$REPORT"'
    grep -q ": \"\${LXQT_WM:=i3}\"" /usr/local/bin/start-lxqt && echo "starter=i3"
    grep -qx "window_manager=i3" /etc/xdg/lxqt/session.conf && echo "session=i3"
    for a in lxqt-desktop lxqt-wallpaper; do grep -qx Hidden=true /etc/xdg/autostart/$a.desktop && echo "hidden=$a"; done
    K=/etc/xdg/lxqt/globalkeyshortcuts.conf/globalkeyshortcuts.conf; [ -f $K ] || K=/etc/xdg/lxqt/globalkeyshortcuts.conf
    for k in E L; do awk -v s="[Control%2BAlt%2B$k." "index(\$0,s)==1{f=1;next} /^\\[/{f=0} f&&/^Enabled=/{print \"key-$k=\" substr(\$0,9)}" $K; done
    grep -q "^DESKTOP=lxqt$" /usr/local/bin/start-i3 && echo "start-i3=lxqt"
')
for s in i3 i3-default i3-ctrl-alt i3-gaps; do
    has "$OUT" "$s=ok" && check "true" "LXQt: $s--setup.sh succeeds" || check "false" "LXQt: $s--setup.sh succeeds" "$OUT"
done
has "$OUT" "config=valid" && has "$OUT" "etc-config=valid" && has "$OUT" "etc-config=includes-ours" && ! has "$OUT" "etc-config=wizard" \
    && check "true" "LXQt: /etc/i3/config (found first: XDG_CONFIG_DIRS=/etc:/etc/xdg) includes ours" \
    || check "false" "LXQt: /etc/i3/config (found first: XDG_CONFIG_DIRS=/etc:/etc/xdg) includes ours" "$OUT"
MODS=$(sed -n 's/^mod-bindings=//p' <<< "$OUT"); TWINS=$(sed -n 's/^twins=//p' <<< "$OUT")
[[ -n "$MODS" && "$MODS" -gt 40 && "$MODS" == "$TWINS" ]] \
    && check "true" "LXQt: a Ctrl+Alt twin for every mod binding ($TWINS)" || check "false" "LXQt: a Ctrl+Alt twin for every mod binding" "mod=$MODS twins=$TWINS"
has "$OUT" "start-i3=lxqt" && has "$OUT" "desktop-icon=yes" \
    && check "true" "LXQt: start-i3 targets LXQt; desktop icon installed" || check "false" "LXQt: start-i3 targets LXQt; desktop icon installed" "$OUT"
has "$OUT" "starter=i3" && has "$OUT" "session=i3" \
    && check "true" "LXQt: start-lxqt and session.conf default to i3" || check "false" "LXQt: start-lxqt and session.conf default to i3" "$OUT"
has "$OUT" "hidden=lxqt-desktop" && has "$OUT" "hidden=lxqt-wallpaper" \
    && check "true" "LXQt: pcmanfm-qt desktop autostarts hidden" || check "false" "LXQt: pcmanfm-qt desktop autostarts hidden" "$OUT"
has "$OUT" "key-E=false" && has "$OUT" "key-L=false" \
    && check "true" "LXQt: Ctrl+Alt+E / Ctrl+Alt+L shortcuts disabled" || check "false" "LXQt: Ctrl+Alt+E / Ctrl+Alt+L shortcuts disabled" "$OUT"

# ---- without +default: installed, but the desktop keeps its own WM ----
OUT=$(in_image "$XFCE_IMAGE" '
    i3--setup.sh >/dev/null 2>&1 && echo "i3=ok"
    grep -q "value=\"xfwm4\"" /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml && echo "session=xfwm4"
    grep -qx Hidden=true /etc/xdg/autostart/xfce-set-wallpaper.desktop || echo "wallpaper-autostart=kept"
')
has "$OUT" "i3=ok" && has "$OUT" "session=xfwm4" && has "$OUT" "wallpaper-autostart=kept" \
    && check "true" "i3 without +default leaves XFCE logging in on xfwm4" || check "false" "i3 without +default leaves XFCE logging in on xfwm4" "$OUT"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ All $NUM checks passed"
else
    echo "❌ $FAILED of $NUM checks failed"
    exit 1
fi
