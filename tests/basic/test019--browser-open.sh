#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth that serves a UI opens it in the host's browser.
#
#   1) a UI booth opens the browser, on its own URL
#   2) it waits for the booth itself — not just nginx — to answer first
#   8) ...and the readiness endpoint it waits on was already ok by then
#   3) --no-browser opens nothing
#   4) CB_BROWSER=false opens nothing
#   5) browser = false in config.toml opens nothing...
#   6) ...and --browser overrides it for the one run
#   7) a booth given a command (-- …) serves no page, so it opens nothing
#
# Case 8 is numbered last but runs with case 2: both interrogate the booth that
# case 1 opened, and each later case replaces that container with its own.
#
# $BROWSER stands in for the real thing: it is the first opener booth tries on
# any Unix host, so pointing it at a script records the open without a window
# appearing on whoever is running the suite. DISPLAY is set for the same reason
# in reverse — on a headless Linux runner booth would correctly refuse to open
# anything, and the point here is the decision, not the host's session.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

# Everything else in the suite runs with CB_BROWSER=false, set by the runners and
# by common--source.sh so a suite never opens windows on whoever started it. This
# test is the exception: opening by default is what it checks, and an inherited
# "off" would turn cases 1, 2 and 6 green for the wrong reason. Each case below
# sets the switch it is testing, so nothing here relies on the ambient value.
unset CB_BROWSER

function generate_name() {
  local name
  while :; do
    name=$(printf "browser-open-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

NAME="$(generate_name)"
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"
LOG="$0.log"
: > "$LOG"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# The stand-in browser: records the URL it was handed, opens nothing.
OPENED="$WORK/opened.txt"
cat > "$WORK/fake-browser.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$1" >> "$OPENED"
EOF
chmod +x "$WORK/fake-browser.sh"
export BROWSER="$WORK/fake-browser.sh"
export DISPLAY="${DISPLAY:-:0}"

# Runs one booth to completion, then reports the URL it opened (empty if none).
# Daemon mode returns once the page is open, so there is no settling to wait on;
# the extra second covers the opener being started rather than waited on.
run_booth() {
  : > "$OPENED"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  {
    echo "=== booth $* ==="
    run_coding_booth --code "$WORK" --variant base --name "$NAME" --port "$PORT" "$@" 2>&1
  } >> "$LOG" || true
  sleep 1
  cat "$OPENED" 2>/dev/null | tr -d '\n'
}

# --- 1 & 2: a UI booth opens its own URL, and the booth answers by then -------
URL="$(run_booth --daemon --keep-alive)"

if [[ "$URL" == "http://localhost:$PORT" ]]; then
  print_test_result "true" "$0" "1" "A UI booth opened http://localhost:$PORT in the browser"
else
  print_test_result "false" "$0" "1" "A UI booth should open http://localhost:$PORT, opened '$URL'"
  tail -30 "$LOG" >&2
  exit 1
fi

# The wait is the feature, and what it waits on is the point. A published port
# accepts connections long before anything inside is listening; nginx then
# answers this variant's root from a file on disk the instant it binds, with the
# ttyd processes behind it still starting. So the assertion is on /s1/ — the
# pane the opened page actually loads — and on the readiness endpoint booth
# waits for. Asserting on '/' would pass with all four panes showing a 502.
PANE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://localhost:$PORT/s1/" 2>/dev/null || echo "000")"
if [[ "$PANE" =~ ^(200|301|302|401|403)$ ]]; then
  print_test_result "true" "$0" "2" "The booth's terminal was already answering ($PANE) when the browser was opened"
else
  print_test_result "false" "$0" "2" "The booth's terminal should have been answering when opened, got '$PANE'"
  tail -30 "$LOG" >&2
  exit 1
fi

HEALTH="$(curl -s --max-time 10 "http://localhost:$PORT/__booth/health" 2>/dev/null || echo "")"
if [[ "$HEALTH" =~ ^ok\  ]]; then
  print_test_result "true" "$0" "8" "The readiness endpoint booth waits on was already ok ($HEALTH)"
else
  print_test_result "false" "$0" "8" "/__booth/health should have been ok when the browser opened, got '${HEALTH:0:80}'"
  tail -30 "$LOG" >&2
  exit 1
fi

# --- 3: --no-browser ---------------------------------------------------------
URL="$(run_booth --daemon --keep-alive --no-browser)"
if [[ -z "$URL" ]]; then
  print_test_result "true" "$0" "3" "--no-browser opened nothing"
else
  print_test_result "false" "$0" "3" "--no-browser should open nothing, opened '$URL'"
  exit 1
fi

# --- 4: CB_BROWSER=false -----------------------------------------------------
URL="$(CB_BROWSER=false run_booth --daemon --keep-alive)"
if [[ -z "$URL" ]]; then
  print_test_result "true" "$0" "4" "CB_BROWSER=false opened nothing"
else
  print_test_result "false" "$0" "4" "CB_BROWSER=false should open nothing, opened '$URL'"
  exit 1
fi

# --- 5 & 6: config.toml, and the per-run override ----------------------------
mkdir -p "$WORK/.booth"
printf 'browser = false\n' > "$WORK/.booth/config.toml"

URL="$(run_booth --daemon --keep-alive)"
if [[ -z "$URL" ]]; then
  print_test_result "true" "$0" "5" "browser = false in config.toml opened nothing"
else
  print_test_result "false" "$0" "5" "browser = false should open nothing, opened '$URL'"
  exit 1
fi

URL="$(run_booth --daemon --keep-alive --browser)"
if [[ "$URL" == "http://localhost:$PORT" ]]; then
  print_test_result "true" "$0" "6" "--browser overrode browser = false for the run"
else
  print_test_result "false" "$0" "6" "--browser should override config.toml, opened '$URL'"
  exit 1
fi

rm -f "$WORK/.booth/config.toml"

# --- 7: a booth given a command has no page ----------------------------------
# `-- …` and --variant terminal reach this identically: the variant resolves to
# base plus a bash command, so both run in the launching terminal and publish a
# port that serves nothing.
URL="$(run_booth -- 'echo booth-ran')"
if [[ -z "$URL" ]]; then
  print_test_result "true" "$0" "7" "A booth given a command opened nothing"
else
  print_test_result "false" "$0" "7" "A command booth should open nothing, opened '$URL'"
  exit 1
fi
