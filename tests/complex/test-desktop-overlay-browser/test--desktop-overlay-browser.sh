#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: desktop overlay behaviour, in a real browser
#
# The wrapper overlay's desktop-only behaviour lives in page JavaScript that
# reaches into the noVNC frame, so a file check proves nothing about it. This
# starts a real XFCE booth (wrapper + noVNC running), copies harness.html next
# to noVNC so it is same-origin, and has the booth's own headless Chrome run
# one scenario per fresh profile:
#   keys      Full screen locks an explicit key list (no PrintScreen/media keys)
#   clipboard hint moves to the Clipboard button, panel dismisses it for good
#   close     closing the bar sends the hint back to the tab
#   drag      dragging the tab changes nothing
#   idle      untouched, the hint hides after a minute (not saved)
#   engaged   bar opened from the tab: the minute no longer applies
#   heading   "Local ⇄ remote" label layout, heading opens the help dialog
# Chrome's --virtual-time-budget fast-forwards the one-minute timers.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: desktop overlay behaviour, in a real browser ==="

FAILED=0
NUM=0
NAME="test-desktop-overlay-browser-$$"
PORT="$(pick_free_port)"
HARNESS=/usr/share/novnc/cb-overlay-harness.html

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

NUM=$((NUM + 1))
if ! booth_step "$NUM" "start a daemon XFCE booth" --name "$NAME" --port "$PORT" --daemon --silence-build; then
  exit 1
fi

READY=false
for _ in $(seq 1 90); do
  if docker exec "$NAME" test -s /tmp/booth-wrapper-serve/index.html 2>/dev/null; then
    READY=true
    break
  fi
  sleep 2
done
if [[ "$READY" != true ]]; then
  print_test_result "false" "$0" "$NUM" "the booth's wrapper page should come up"
  exit 1
fi
print_test_result "true" "$0" "$NUM" "daemon XFCE booth is up with its wrapper page"

# Google publishes no linux/arm64 Chrome, and the variant installs no other.
if ! docker exec "$NAME" bash -c 'command -v google-chrome' >/dev/null 2>&1; then
  echo "SKIP: no google-chrome in the desktop-xfce image on this architecture ($(uname -m))"
  exit 0
fi

docker cp harness.html "$NAME:$HARNESS" >/dev/null
docker exec -u root "$NAME" chmod 0644 "$HARNESS"

# The wrapper page file exists before nginx and noVNC's web server are serving it,
# and Chrome would then load an error page (no harness output at all). Wait on the
# same path Chrome takes: the harness URL through the booth port.
SERVING=false
for _ in $(seq 1 90); do
  if docker exec "$NAME" curl -sf -o /dev/null http://localhost:10000/cb-overlay-harness.html \
     && docker exec "$NAME" curl -sf -o /dev/null http://localhost:10000/booth; then
    SERVING=true
    break
  fi
  sleep 2
done
if [[ "$SERVING" != true ]]; then
  NUM=$((NUM + 1))
  print_test_result "false" "$0" "$NUM" "the booth port should serve the wrapper and the harness"
  exit 1
fi

run_scenario() {
  local scenario="$1" budget="$2"
  docker exec -u coder "$NAME" bash -c "
    timeout 240 google-chrome --headless=new --no-sandbox --disable-gpu \
      --user-data-dir=\"\$(mktemp -d)\" --window-size=1400,1000 \
      --virtual-time-budget=$budget --dump-dom 'http://localhost:10000/cb-overlay-harness.html#$scenario' 2>/dev/null
  " | sed -n '/<pre id="out">/,/<\/pre>/p' \
    | sed -e 's/<[^>]*>//g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' \
    | grep -v '^$' || true
}

for entry in keys:20000 clipboard:20000 close:20000 drag:20000 heading:20000 idle:85000 engaged:85000; do
  scenario="${entry%%:*}" budget="${entry#*:}"
  output="$(run_scenario "$scenario" "$budget")"
  while IFS= read -r line; do
    case "$line" in
      "PASS "*)
        NUM=$((NUM + 1))
        print_test_result "true" "$0" "$NUM" "[$scenario] ${line#PASS }"
        ;;
      "FAIL "*)
        NUM=$((NUM + 1))
        print_test_result "false" "$0" "$NUM" "[$scenario] ${line#FAIL }"
        FAILED=$((FAILED + 1))
        ;;
    esac
  done <<<"$output"
  if ! grep -qx "DONE" <<<"$output"; then
    NUM=$((NUM + 1))
    print_test_result "false" "$0" "$NUM" "[$scenario] should run to the end"
    echo "  Output: ${output:-<empty>}"
    FAILED=$((FAILED + 1))
  fi
done

exit $FAILED
