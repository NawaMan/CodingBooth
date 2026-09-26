#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the sway setups, and start-wayland's compositor choice, in a real
# Wayland image
#
# Runs the repo's wayland--setup.sh (for its start-wayland) and the sway setups
# (sway, sway-ctrl-alt, sway-gaps) in a throwaway container of the Wayland
# image — the setups are mounted in, so the image only has to carry the
# desktop — then asserts what they leave behind and starts real headless
# sessions with start-wayland:
#   - with no compositor chosen it runs labwc, as it always has;
#   - after the sway setups it runs sway, with the waybar panel;
#   - WAYLAND_COMPOSITOR=labwc brings labwc back for a run;
#   - an unknown WAYLAND_COMPOSITOR fails with an explanation.
#   - on either compositor, cb-display-resize (the hook the booth page drives
#     to fit the browser) resizes the live output.
# No booth is started; the key bindings through noVNC were checked by hand.
#
# Image: CB_WAYLAND_IMAGE (default: the -latest desktop-wayland image).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
WAYLAND_IMAGE="${CB_WAYLAND_IMAGE:-nawaman/codingbooth:desktop-wayland-latest}"

echo "=== Test: sway setups and start-wayland's compositor choice ==="

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
for s in wayland sway sway-ctrl-alt sway-gaps; do
    MOUNTS+=(-v "$SETUPS/$s--setup.sh:/opt/codingbooth/setups/$s--setup.sh:ro")
done

# in_image <script> — run <script> in a throwaway Wayland container; prints its output.
in_image() {
    docker image inspect "$WAYLAND_IMAGE" >/dev/null 2>&1 || docker pull -q "$WAYLAND_IMAGE" >/dev/null
    docker run --rm "${MOUNTS[@]}" --entrypoint bash "$WAYLAND_IMAGE" -c "
        export PATH=/opt/codingbooth/setups:\$PATH
        $1" < /dev/null 2>&1
}

# has <output> <line> — the output contains exactly that line.
has() { grep -qxF -- "$2" <<< "$1"; }

# session <label> [VAR=value…] — start-wayland as an ordinary user, report what
# runs once wayvnc is up, then stop it.
SESSION='
    useradd -m cbtest >/dev/null 2>&1 || true
    session() {
        local label="$1"; shift
        runuser -u cbtest -- env HOME=/home/cbtest "$@" bash -c "start-wayland >/tmp/$label.log 2>&1 &"
        for _ in $(seq 1 40); do
            pgrep -x wayvnc >/dev/null && break
            grep -q "❌" /tmp/$label.log 2>/dev/null && break
            sleep 1
        done
        sleep 2
        if pgrep -x sway >/dev/null; then echo "$label=sway"
        elif pgrep -x labwc >/dev/null; then echo "$label=labwc"
        else echo "$label=none"; sed -n "1,5p" /tmp/$label.log; fi
        pgrep -x wayvnc >/dev/null && echo "$label-wayvnc=yes"
        pgrep -x waybar >/dev/null && echo "$label-waybar=yes"
        grep -q "\"sway/workspaces\"" /home/cbtest/.config/waybar/config.jsonc 2>/dev/null && echo "$label-workspaces=yes"
        # What the booth page does (through the API server) to fit the browser.
        if runuser -u cbtest -- env HOME=/home/cbtest cb-display-resize 1600 900 >/dev/null 2>&1; then
            local rt=/tmp/xdg-$(id -u cbtest)
            runuser -u cbtest -- env XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=$(cat $rt/cb-wayland-display) wlr-randr \
                | grep -qE "^ +1600x900 px.*current" && echo "$label-resize=1600x900"
        fi
        grep -q "❌" /tmp/$label.log && grep "❌" /tmp/$label.log | sed "s/^/$label-error=/"
        pkill -u cbtest >/dev/null 2>&1; sleep 2; pkill -9 -u cbtest >/dev/null 2>&1; sleep 1
        rm -rf /tmp/xdg-$(id -u cbtest)
    }
'

# ---- the template's default selection: sway + ctrl-alt + gaps ----
OUT=$(in_image "$SESSION"'
    wayland--setup.sh >/tmp/wayland.log 2>&1 && echo "wayland=ok" || { echo "wayland=FAILED"; tail -5 /tmp/wayland.log; }
    session before-sway

    for s in "sway alt" sway-ctrl-alt "sway-gaps 8"; do
        set -- $s
        $1--setup.sh "${@:2}" >/tmp/$1.log 2>&1 && echo "$1=ok" || { echo "$1=FAILED"; tail -5 /tmp/$1.log; }
    done
    D=$(mktemp -d)
    XDG_RUNTIME_DIR=$D WLR_BACKENDS=headless WLR_RENDERER=pixman sway --unsupported-gpu -C -c /etc/sway/config >/dev/null 2>&1 && echo "config=valid"
    echo "compositor-file=$(cat /opt/codingbooth/wayland-compositor)"
    grep -qx "set \$mod Mod1" /etc/sway/config && echo "mod=Mod1"
    echo "mod-bindings=$(grep -c "^bindsym \$mod+" /etc/sway/config)"
    echo "twins=$(grep -c "^bindsym Ctrl+Mod1+" /etc/sway/config.d/ctrl-alt.conf)"
    grep -qx "gaps inner 8" /etc/sway/config.d/gaps.conf && echo "gaps=8"
    sway-gaps--setup.sh wide >/dev/null 2>&1 || echo "bad-gap=rejected"
    grep -q "^output \* bg /usr/share/backgrounds/codingbooth/wallpaper.jpg fill$" /etc/sway/config && echo "wallpaper=yes"
    grep -q "swaybar_command waybar" /etc/sway/config && echo "bar=waybar"
    ls /usr/local/share/booth-message-wrapper/plugins/ 2>/dev/null | sed "s/^/plugin=/"

    session with-sway
    session override WAYLAND_COMPOSITOR=labwc
    session bogus WAYLAND_COMPOSITOR=weston
')
has "$OUT" "wayland=ok" && has "$OUT" "before-sway=labwc" && has "$OUT" "before-sway-wayvnc=yes" && ! has "$OUT" "before-sway-workspaces=yes" \
    && check "true" "No compositor chosen: start-wayland runs labwc, as before" \
    || check "false" "No compositor chosen: start-wayland runs labwc, as before" "$OUT"
for s in sway sway-ctrl-alt sway-gaps; do
    has "$OUT" "$s=ok" && check "true" "$s--setup.sh succeeds" || check "false" "$s--setup.sh succeeds" "$OUT"
done
has "$OUT" "config=valid" && has "$OUT" "compositor-file=sway" && has "$OUT" "mod=Mod1" \
    && check "true" "sway config validates; sway chosen for start-wayland; Alt is the mod" \
    || check "false" "sway config validates; sway chosen for start-wayland; Alt is the mod" "$OUT"
MODS=$(sed -n 's/^mod-bindings=//p' <<< "$OUT"); TWINS=$(sed -n 's/^twins=//p' <<< "$OUT")
[[ -n "$MODS" && "$MODS" -gt 40 && "$MODS" == "$TWINS" ]] \
    && check "true" "A Ctrl+Alt twin for every mod binding ($TWINS)" || check "false" "A Ctrl+Alt twin for every mod binding" "mod=$MODS twins=$TWINS"
has "$OUT" "gaps=8" && has "$OUT" "bad-gap=rejected" \
    && check "true" "8px gaps; a non-numeric gap is rejected" || check "false" "8px gaps; a non-numeric gap is rejected" "$OUT"
has "$OUT" "wallpaper=yes" && has "$OUT" "bar=waybar" \
    && check "true" "The wallpaper and the waybar panel carry over" || check "false" "The wallpaper and the waybar panel carry over" "$OUT"
has "$OUT" "plugin=sway-00-ctrl-alt.js" && has "$OUT" "plugin=sway-help.js" \
    && check "true" "Help plugins, Ctrl+Alt flag first" || check "false" "Help plugins, Ctrl+Alt flag first" "$OUT"
has "$OUT" "with-sway=sway" && has "$OUT" "with-sway-wayvnc=yes" && has "$OUT" "with-sway-waybar=yes" && has "$OUT" "with-sway-workspaces=yes" \
    && check "true" "start-wayland runs sway, with wayvnc and the panel (workspaces shown)" \
    || check "false" "start-wayland runs sway, with wayvnc and the panel (workspaces shown)" "$OUT"
has "$OUT" "before-sway-resize=1600x900" && has "$OUT" "with-sway-resize=1600x900" \
    && check "true" "cb-display-resize resizes a live labwc and a live sway output" \
    || check "false" "cb-display-resize resizes a live labwc and a live sway output" "$OUT"
has "$OUT" "override=labwc" && has "$OUT" "override-wayvnc=yes" \
    && check "true" "WAYLAND_COMPOSITOR=labwc brings labwc back for a run" \
    || check "false" "WAYLAND_COMPOSITOR=labwc brings labwc back for a run" "$OUT"
has "$OUT" "bogus=none" && grep -q "^bogus-error=.*Unknown WAYLAND_COMPOSITOR 'weston'" <<< "$OUT" \
    && check "true" "An unknown WAYLAND_COMPOSITOR fails with an explanation" \
    || check "false" "An unknown WAYLAND_COMPOSITOR fails with an explanation" "$OUT"

# ---- sway:super without +ctrl-alt ----
OUT=$(in_image '
    wayland--setup.sh >/dev/null 2>&1
    sway--setup.sh super >/tmp/s.log 2>&1 && echo "sway=ok" || tail -5 /tmp/s.log
    grep -qx "set \$mod Mod4" /etc/sway/config && echo "mod=Mod4"
    [ -e /etc/sway/config.d/ctrl-alt.conf ] || echo "twins=none"
    grep -q "|| \"Super\"" /usr/local/share/booth-message-wrapper/plugins/sway-help.js && echo "help-keys=Super"
')
has "$OUT" "sway=ok" && has "$OUT" "mod=Mod4" && has "$OUT" "twins=none" && has "$OUT" "help-keys=Super" \
    && check "true" "sway:super uses Super, and without +ctrl-alt has no twins" \
    || check "false" "sway:super uses Super, and without +ctrl-alt has no twins" "$OUT"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ All $NUM checks passed"
else
    echo "❌ $FAILED of $NUM checks failed"
    exit 1
fi
