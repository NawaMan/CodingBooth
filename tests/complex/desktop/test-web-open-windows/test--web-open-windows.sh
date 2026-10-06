#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth web app opens one clean window
#
# Clicking a web-service icon runs cb-web-open, which starts the service with
# its START_CMD and then opens its own Chrome --app window. Two things got in
# the way of that being the only window, and both are asserted here, in a
# throwaway container of the XFCE image with the repo's setups mounted in:
#   - start-viewmd ran viewmd without --server-only, and viewmd opens a browser
#     by default, so the first click opened two windows. A fake $BROWSER that
#     leaves a marker shows whether viewmd still reaches for one.
#   - Chrome showed "You are using an unsupported command-line flag:
#     --no-sandbox" on every window. A managed policy turns that off.
# That the app windows tile under i3 / sway is in test-i3-desktops and
# test-sway-wayland.
#
# Image: CB_XFCE_IMAGE (default: the -latest XFCE image). google-chrome--setup.sh
# runs apt, so this needs the network.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
XFCE_IMAGE="${CB_XFCE_IMAGE:-nawaman/codingbooth:desktop-xfce-latest}"

echo "=== Test: a booth web app opens one clean window ==="

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

# has <output> <line> — the output contains exactly that line.
has() { grep -qxF -- "$2" <<< "$1"; }

docker image inspect "$XFCE_IMAGE" >/dev/null 2>&1 || docker pull -q "$XFCE_IMAGE" >/dev/null
OUT=$(docker run --rm \
    -v "$SETUPS/viewmd-desktop-icon--setup.sh:/opt/codingbooth/setups/viewmd-desktop-icon--setup.sh:ro" \
    -v "$SETUPS/google-chrome--setup.sh:/opt/codingbooth/setups/google-chrome--setup.sh:ro" \
    --entrypoint bash "$XFCE_IMAGE" -c '
    export PATH=/opt/codingbooth/setups:$PATH
    for s in viewmd-desktop-icon google-chrome; do
        $s--setup.sh >/tmp/$s.log 2>&1 && echo "$s=ok" || { echo "$s=FAILED"; tail -5 /tmp/$s.log; }
    done

    # Start viewmd the way cb-web-open does, with a browser that only leaves a mark.
    printf "#!/bin/sh\ntouch /tmp/browser-called\n" > /tmp/fake-browser
    chmod +x /tmp/fake-browser
    BROWSER=/tmp/fake-browser nohup start-viewmd 18765 /tmp >/tmp/viewmd.log 2>&1 &
    for _ in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/18765) 2>/dev/null && break; sleep 0.5; done
    (exec 3<>/dev/tcp/127.0.0.1/18765) 2>/dev/null && echo "viewmd=serving"
    sleep 2   # viewmd opens its browser right after it starts listening
    [ -e /tmp/browser-called ] && echo "viewmd-browser=opened" || echo "viewmd-browser=none"

    python3 -c "import json; print(\"chrome-flag-warnings=%s\" % json.load(open(\"/etc/opt/chrome/policies/managed/codingbooth.json\"))[\"CommandLineFlagSecurityWarningsEnabled\"])" 2>&1
' < /dev/null 2>&1) || true   # a failed step is reported by the checks below, not by set -e

for s in viewmd-desktop-icon google-chrome; do
    has "$OUT" "$s=ok" && check "true" "$s--setup.sh succeeds" || check "false" "$s--setup.sh succeeds" "$OUT"
done
has "$OUT" "viewmd=serving" && has "$OUT" "viewmd-browser=none" \
    && check "true" "start-viewmd serves without opening a browser of its own" \
    || check "false" "start-viewmd serves without opening a browser of its own" "$OUT"
has "$OUT" "chrome-flag-warnings=False" \
    && check "true" "Chrome policy hides the --no-sandbox warning bar" \
    || check "false" "Chrome policy hides the --no-sandbox warning bar" "$OUT"

[[ "$FAILED" -eq 0 ]] || exit 1
