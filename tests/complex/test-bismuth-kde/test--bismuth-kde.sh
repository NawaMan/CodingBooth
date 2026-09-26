#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the Bismuth setups inside a real KDE image
#
# Runs the repo's bismuth--setup.sh and its two extension setups
# (bismuth-default, bismuth-gaps) in throwaway containers of the KDE image — the
# setups are mounted in, so the image only has to carry the desktop — and
# asserts what they leave behind. No booth and no session is started.
#
# The headline check is that KWin can load the script at all: Ubuntu 24.04's
# kwin-bismuth ships ES2022 `static { … }` blocks that Qt 5's JavaScript parser
# rejects, and bismuth--setup.sh rewrites them. qmllint (Qt 5's parser,
# installed into the throwaway container) is the witness — it rejects the
# packaged file with the same error KWin logs.
#
# Image: CB_KDE_IMAGE (default: the -latest desktop-kde image).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
KDE_IMAGE="${CB_KDE_IMAGE:-nawaman/codingbooth:desktop-kde-latest}"

echo "=== Test: Bismuth setups inside a real KDE image ==="

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
for s in bismuth bismuth-default bismuth-gaps; do
    MOUNTS+=(-v "$SETUPS/$s--setup.sh:/opt/codingbooth/setups/$s--setup.sh:ro")
done

# in_image <script> — run <script> in a throwaway KDE container; prints its output.
in_image() {
    docker image inspect "$KDE_IMAGE" >/dev/null 2>&1 || docker pull -q "$KDE_IMAGE" >/dev/null
    docker run --rm "${MOUNTS[@]}" --entrypoint bash "$KDE_IMAGE" -c "
        export PATH=/opt/codingbooth/setups:\$PATH
        $1" < /dev/null 2>&1
}

# has <output> <line> — the output contains exactly that line.
has() { grep -qxF -- "$2" <<< "$1"; }

# ---- the template's default selection: bismuth + default + gaps ----
OUT=$(in_image '
    for s in "bismuth ctrl-alt" bismuth-default "bismuth-gaps 8"; do
        set -- $s
        $1--setup.sh "${@:2}" >/tmp/$1.log 2>&1 && echo "$1=ok" || { echo "$1=FAILED"; tail -5 /tmp/$1.log; }
    done

    JS=/usr/share/kwin/scripts/bismuth/contents/code/index.mjs
    grep -qE "^\s*static \{" $JS && echo "js=static-blocks-left"
    grep -qx "FloatingLayout.instance = new FloatingLayout();" $JS && echo "js=inner-name-rewritten"
    # apt--install.sh cleared the lists after installing kwin-bismuth.
    apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qtdeclarative5-dev-tools >/dev/null 2>&1
    /usr/lib/qt5/bin/qmllint $JS >/tmp/lint.log 2>&1 && echo "qt5-parse=ok" || { echo "qt5-parse=FAILED"; head -3 /tmp/lint.log; }

    for c in start-bismuth stop-bismuth; do [ -x /usr/local/bin/$c ] && echo "cmd=$c"; done
    [ -f /etc/skel/Desktop/cb-bismuth-start.desktop ] && echo "desktop-icon=yes"
    [ -f /usr/share/applications/cb-bismuth-stop.desktop ] && echo "leave-entry=yes"
    ls /usr/local/share/booth-message-wrapper/plugins/ 2>/dev/null | sed "s/^/plugin=/"
    grep -q "var K = \"Ctrl+Alt\"" /usr/local/share/booth-message-wrapper/plugins/bismuth-help.js && echo "help-keys=Ctrl+Alt"

    echo "enabled=$(kreadconfig5 --file /etc/xdg/kwinrc --group Plugins --key bismuthEnabled)"
    for k in tileLayoutGap screenGapLeft screenGapRight screenGapTop screenGapBottom; do
        echo "gap-$k=$(kreadconfig5 --file /etc/xdg/kwinrc --group Script-bismuth --key $k)"
    done
    bismuth-gaps--setup.sh wide >/dev/null 2>&1 || echo "bad-gap=rejected"

    # The startup hook, as a user with a fresh home, then again over a user rebinding.
    H=$(mktemp -d); chmod 755 $H
    HOOK=/usr/share/startup.d/57-cb-bismuth--startup.sh
    [ -x $HOOK ] && echo "hook=yes"
    HOME=$H $HOOK && echo "hook-rc=0"
    F=$H/.config/kglobalshortcutsrc
    echo "seeded=$(sed -n "/^\[bismuth\]/,/^\[/p" $F | grep -c "=Ctrl+Alt+")"
    grep -xF "next_layout=Ctrl+Alt+\\\\\\\\,Meta+\\\\\\\\,Switch to the Next Layout" $F >/dev/null && echo "backslash=list-escaped"
    grep -xF "prev_layout=Ctrl+Alt+|,Meta+|,Switch to the Previous Layout" $F >/dev/null && echo "prev=bar"
    grep -xF "focus_left_window=Ctrl+Alt+H,Meta+H,Focus Left Window" $F >/dev/null && echo "focus-left=Ctrl+Alt+H"
    grep -q "=Ctrl+Alt+T," $F && echo "ctrl-alt-t=taken"
    HOME=$H kwriteconfig5 --file kglobalshortcutsrc --group bismuth --key focus_left_window "Meta+H,Meta+H,Focus Left Window"
    HOME=$H $HOOK
    grep -xF "focus_left_window=Meta+H,Meta+H,Focus Left Window" $F >/dev/null && echo "rebinding=kept"
')
for s in bismuth bismuth-default bismuth-gaps; do
    has "$OUT" "$s=ok" && check "true" "$s--setup.sh succeeds" || check "false" "$s--setup.sh succeeds" "$OUT"
done
has "$OUT" "qt5-parse=ok" && ! has "$OUT" "js=static-blocks-left" && has "$OUT" "js=inner-name-rewritten" \
    && check "true" "The packaged Bismuth script now parses under Qt 5 (static blocks rewritten)" \
    || check "false" "The packaged Bismuth script now parses under Qt 5 (static blocks rewritten)" "$OUT"
has "$OUT" "cmd=start-bismuth" && has "$OUT" "cmd=stop-bismuth" \
    && check "true" "start-bismuth / stop-bismuth installed" || check "false" "start-bismuth / stop-bismuth installed" "$OUT"
has "$OUT" "desktop-icon=yes" && has "$OUT" "leave-entry=yes" \
    && check "true" "Desktop icon and a Leave Tiling menu entry" || check "false" "Desktop icon and a Leave Tiling menu entry" "$OUT"
has "$OUT" "plugin=bismuth-help.js" && has "$OUT" "help-keys=Ctrl+Alt" \
    && check "true" "Help tab plugin lists the Ctrl+Alt keys" || check "false" "Help tab plugin lists the Ctrl+Alt keys" "$OUT"
has "$OUT" "enabled=true" \
    && check "true" "+default: Bismuth on in KWin's system default" || check "false" "+default: Bismuth on in KWin's system default" "$OUT"
GAPS=$(grep -c '^gap-.*=8$' <<< "$OUT" || true)
[[ "$GAPS" -eq 5 ]] && has "$OUT" "bad-gap=rejected" \
    && check "true" "+gaps: 8px tile and screen gaps; a non-numeric gap is rejected" \
    || check "false" "+gaps: 8px tile and screen gaps; a non-numeric gap is rejected" "$OUT"
has "$OUT" "hook=yes" && has "$OUT" "hook-rc=0" && has "$OUT" "seeded=23" && has "$OUT" "focus-left=Ctrl+Alt+H" \
    && check "true" "Startup hook seeds all 23 Bismuth shortcuts on Ctrl+Alt" \
    || check "false" "Startup hook seeds all 23 Bismuth shortcuts on Ctrl+Alt" "$OUT"
has "$OUT" "backslash=list-escaped" && has "$OUT" "prev=bar" \
    && check "true" "Ctrl+Alt+\\ is list-escaped and the previous layout is Ctrl+Alt+|" \
    || check "false" "Ctrl+Alt+\\ is list-escaped and the previous layout is Ctrl+Alt+|" "$OUT"
! has "$OUT" "ctrl-alt-t=taken" \
    && check "true" "Ctrl+Alt+T is left to Konsole" || check "false" "Ctrl+Alt+T is left to Konsole" "$OUT"
has "$OUT" "rebinding=kept" \
    && check "true" "A shortcut the user rebound survives the next start" || check "false" "A shortcut the user rebound survives the next start" "$OUT"

# ---- bismuth:meta without +default: Bismuth's own keys, off at login ----
OUT=$(in_image '
    bismuth--setup.sh meta >/tmp/b.log 2>&1 && echo "bismuth=ok" || tail -5 /tmp/b.log
    [ -e /usr/share/startup.d/57-cb-bismuth--startup.sh ] || echo "hook=none"
    grep -q "var K = \"Meta\"" /usr/local/share/booth-message-wrapper/plugins/bismuth-help.js && echo "help-keys=Meta"
    [ -z "$(kreadconfig5 --file /etc/xdg/kwinrc --group Plugins --key bismuthEnabled)" ] && echo "enabled=unset"
')
has "$OUT" "bismuth=ok" && has "$OUT" "hook=none" && has "$OUT" "help-keys=Meta" \
    && check "true" "bismuth:meta keeps Bismuth's Meta keys (no startup hook)" \
    || check "false" "bismuth:meta keeps Bismuth's Meta keys (no startup hook)" "$OUT"
has "$OUT" "enabled=unset" \
    && check "true" "Without +default, KWin's default leaves Bismuth off" || check "false" "Without +default, KWin's default leaves Bismuth off" "$OUT"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ All $NUM checks passed"
else
    echo "❌ $FAILED of $NUM checks failed"
    exit 1
fi
