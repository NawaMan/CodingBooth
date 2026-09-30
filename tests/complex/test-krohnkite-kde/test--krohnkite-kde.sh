#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the Krohnkite setups inside a real KDE (Plasma 6) image
#
# Runs the repo's krohnkite--setup.sh and its two extension setups
# (krohnkite-default, krohnkite-gaps) in throwaway containers of the KDE image
# — the setups are mounted in, so the image only has to carry the desktop — and
# asserts what they leave behind. No booth and no session is started.
#
# The headline check is that Plasma's own package loader (kpackagetool6, the
# same KPackage code KWin uses to find scripts) recognises the unpacked
# Krohnkite as a KWin script. The deprecated bismuth setups are checked to
# install Krohnkite in their place.
#
# Image: CB_KDE_IMAGE (default: the desktop-kde image of this checkout's
# version.txt — -latest may still be a Plasma 5 release, where Krohnkite skips).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
VERSION="$(tr -d ' \t\n\r' < "$REPO_ROOT/version.txt")"
KDE_IMAGE="${CB_KDE_IMAGE:-nawaman/codingbooth:desktop-kde-${VERSION}}"

echo "=== Test: Krohnkite setups inside a real KDE image ==="

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
for s in krohnkite krohnkite-default krohnkite-gaps bismuth bismuth-default bismuth-gaps; do
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

# ---- the template's default selection: krohnkite + default + gaps ----
OUT=$(in_image '
    for s in "krohnkite ctrl-alt" krohnkite-default "krohnkite-gaps 8"; do
        set -- $s
        $1--setup.sh "${@:2}" >/tmp/$1.log 2>&1 && echo "$1=ok" || { echo "$1=FAILED"; tail -5 /tmp/$1.log; }
    done

    kpackagetool6 --type KWin/Script --list --global 2>/dev/null | grep -qx krohnkite && echo "kpackage=listed"
    kpackagetool6 --type KWin/Script --show krohnkite --global 2>/dev/null | grep -q "Path *: /usr/share/kwin/scripts/krohnkite/" && echo "kpackage-path=system"
    grep -q "\"Version\": \"0.9.9.2\"" /usr/share/kwin/scripts/krohnkite/metadata.json && echo "version=0.9.9.2"

    for c in start-krohnkite stop-krohnkite; do [ -x /usr/local/bin/$c ] && echo "cmd=$c"; done
    [ -f /etc/skel/Desktop/cb-krohnkite-start.desktop ] && echo "desktop-icon=yes"
    [ -f /usr/share/applications/cb-krohnkite-stop.desktop ] && echo "leave-entry=yes"
    ls /usr/local/share/booth-message-wrapper/plugins/ 2>/dev/null | sed "s/^/plugin=/"
    grep -q "var K = \"Ctrl+Alt\"" /usr/local/share/booth-message-wrapper/plugins/krohnkite-help.js && echo "help-keys=Ctrl+Alt"

    echo "enabled=$(kreadconfig6 --file /etc/xdg/kwinrc --group Plugins --key krohnkiteEnabled)"
    for k in screenGapBetween screenGapLeft screenGapRight screenGapTop screenGapBottom; do
        echo "gap-$k=$(kreadconfig6 --file /etc/xdg/kwinrc --group Script-krohnkite --key $k)"
    done
    krohnkite-gaps--setup.sh wide >/dev/null 2>&1 || echo "bad-gap=rejected"

    # The startup hook, as a user with a fresh home, then again over a user rebinding.
    H=$(mktemp -d); chmod 755 $H
    HOOK=/usr/share/startup.d/57-cb-krohnkite--startup.sh
    [ -x $HOOK ] && echo "hook=yes"
    HOME=$H $HOOK && echo "hook-rc=0"
    F=$H/.config/kglobalshortcutsrc
    echo "seeded=$(sed -n "/^\[kwin\]/,/^\[/p" $F | grep -c "^Krohnkite.*=Ctrl+Alt+")"
    grep -E "^Krohnkite(FocusLeft|FocusPrev|NextLayout|PreviousLayout)=" $F | sed "s/^/line=/"
    grep -q "=Ctrl+Alt+T," $F && echo "ctrl-alt-t=taken"
    HOME=$H kwriteconfig6 --file kglobalshortcutsrc --group kwin --key KrohnkiteFocusLeft "Meta+H,Meta+H,Krohnkite: Focus Left"
    HOME=$H $HOOK
    grep -xF "KrohnkiteFocusLeft=Meta+H,Meta+H,Krohnkite: Focus Left" $F >/dev/null && echo "rebinding=kept"
')
for s in krohnkite krohnkite-default krohnkite-gaps; do
    has "$OUT" "$s=ok" && check "true" "$s--setup.sh succeeds" || check "false" "$s--setup.sh succeeds" "$OUT"
done
has "$OUT" "kpackage=listed" && has "$OUT" "kpackage-path=system" && has "$OUT" "version=0.9.9.2" \
    && check "true" "Plasma's package loader finds Krohnkite 0.9.9.2 as a KWin script" \
    || check "false" "Plasma's package loader finds Krohnkite 0.9.9.2 as a KWin script" "$OUT"
has "$OUT" "cmd=start-krohnkite" && has "$OUT" "cmd=stop-krohnkite" \
    && check "true" "start-krohnkite / stop-krohnkite installed" || check "false" "start-krohnkite / stop-krohnkite installed" "$OUT"
has "$OUT" "desktop-icon=yes" && has "$OUT" "leave-entry=yes" \
    && check "true" "Desktop icon and a Leave Tiling menu entry" || check "false" "Desktop icon and a Leave Tiling menu entry" "$OUT"
has "$OUT" "plugin=krohnkite-help.js" && has "$OUT" "help-keys=Ctrl+Alt" \
    && check "true" "Help tab plugin lists the Ctrl+Alt keys" || check "false" "Help tab plugin lists the Ctrl+Alt keys" "$OUT"
has "$OUT" "enabled=true" \
    && check "true" "+default: Krohnkite on in KWin's system default" || check "false" "+default: Krohnkite on in KWin's system default" "$OUT"
GAPS=$(grep -c '^gap-.*=8$' <<< "$OUT" || true)
[[ "$GAPS" -eq 5 ]] && has "$OUT" "bad-gap=rejected" \
    && check "true" "+gaps: 8px tile and screen gaps; a non-numeric gap is rejected" \
    || check "false" "+gaps: 8px tile and screen gaps; a non-numeric gap is rejected" "$OUT"
has "$OUT" "hook=yes" && has "$OUT" "hook-rc=0" && has "$OUT" "seeded=25" \
    && has "$OUT" 'line=KrohnkiteFocusLeft=Ctrl+Alt+H,Meta+H,Krohnkite: Focus Left' \
    && check "true" "Startup hook seeds all 25 Krohnkite shortcuts on Ctrl+Alt" \
    || check "false" "Startup hook seeds all 25 Krohnkite shortcuts on Ctrl+Alt" "$OUT"
has "$OUT" 'line=KrohnkiteNextLayout=Ctrl+Alt+\\\\,Meta+\\\\,Krohnkite: Next Layout' \
    && has "$OUT" 'line=KrohnkiteFocusPrev=Ctrl+Alt+\\,,Meta+\\,,Krohnkite: Focus Previous' \
    && has "$OUT" 'line=KrohnkitePreviousLayout=Ctrl+Alt+|,Meta+|,Krohnkite: Previous Layout' \
    && check "true" "Ctrl+Alt+\\ and Ctrl+Alt+, are list-escaped; the previous layout is Ctrl+Alt+|" \
    || check "false" "Ctrl+Alt+\\ and Ctrl+Alt+, are list-escaped; the previous layout is Ctrl+Alt+|" "$OUT"
! has "$OUT" "ctrl-alt-t=taken" \
    && check "true" "Ctrl+Alt+T is left to Konsole" || check "false" "Ctrl+Alt+T is left to Konsole" "$OUT"
has "$OUT" "rebinding=kept" \
    && check "true" "A shortcut the user rebound survives the next start" || check "false" "A shortcut the user rebound survives the next start" "$OUT"

# ---- krohnkite:meta without +default: Krohnkite's own keys, off at login ----
OUT=$(in_image '
    krohnkite--setup.sh meta >/tmp/k.log 2>&1 && echo "krohnkite=ok" || tail -5 /tmp/k.log
    [ -e /usr/share/startup.d/57-cb-krohnkite--startup.sh ] || echo "hook=none"
    grep -q "var K = \"Meta\"" /usr/local/share/booth-message-wrapper/plugins/krohnkite-help.js && echo "help-keys=Meta"
    [ -z "$(kreadconfig6 --file /etc/xdg/kwinrc --group Plugins --key krohnkiteEnabled)" ] && echo "enabled=unset"
')
has "$OUT" "krohnkite=ok" && has "$OUT" "hook=none" && has "$OUT" "help-keys=Meta" \
    && check "true" "krohnkite:meta keeps Krohnkite's Meta keys (no startup hook)" \
    || check "false" "krohnkite:meta keeps Krohnkite's Meta keys (no startup hook)" "$OUT"
has "$OUT" "enabled=unset" \
    && check "true" "Without +default, KWin's default leaves Krohnkite off" || check "false" "Without +default, KWin's default leaves Krohnkite off" "$OUT"

# ---- an old Boothfile's `setup bismuth*` lines install Krohnkite instead ----
OUT=$(in_image '
    bismuth--setup.sh ctrl-alt >/tmp/b.log 2>&1 && echo "bismuth=ok" || tail -5 /tmp/b.log
    grep -q "bismuth--setup.sh is deprecated" /tmp/b.log && echo "notice=yes"
    bismuth-default--setup.sh >/dev/null 2>&1 && bismuth-gaps--setup.sh 4 >/dev/null 2>&1 && echo "extensions=ok"
    [ -x /usr/local/bin/start-krohnkite ] && echo "cmd=start-krohnkite"
    echo "enabled=$(kreadconfig6 --file /etc/xdg/kwinrc --group Plugins --key krohnkiteEnabled)"
    echo "gap=$(kreadconfig6 --file /etc/xdg/kwinrc --group Script-krohnkite --key screenGapBetween)"
')
has "$OUT" "bismuth=ok" && has "$OUT" "notice=yes" && has "$OUT" "extensions=ok" && has "$OUT" "cmd=start-krohnkite" \
    && has "$OUT" "enabled=true" && has "$OUT" "gap=4" \
    && check "true" "The deprecated bismuth setups install and configure Krohnkite, with a notice" \
    || check "false" "The deprecated bismuth setups install and configure Krohnkite, with a notice" "$OUT"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ All $NUM checks passed"
else
    echo "❌ $FAILED of $NUM checks failed"
    exit 1
fi
