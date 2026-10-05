#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `booth logs` — container output, service log files, and a stopped booth.
#
# A keep-alive base booth runs a .booth/startups/ script that prints a line to
# stdout (container output) and writes service logs into /tmp: svc.log, a
# fam-a.log/fam-b.log family, and a ticker that keeps appending. Then:
#   1) `booth logs` shows the startup script's stdout
#   2) `booth logs svc` shows /tmp/svc.log
#   3) `booth logs fam` shows the whole fam-* family, with tail's headers
#   4) `booth logs --list` names the services
#   5) `booth logs --startup` shows /tmp/startups.log
#   6) interrupting `booth logs ticker -f` leaves no tail behind in the booth
#   7) once the booth is stopped, `booth logs` and `booth logs svc` still answer
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "booth-logs-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

# Find the codingbooth binary for the logs subcommand (no --version).
BOOTH_BIN="$(find_local_booth_build)" || {
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
}

run_booth() {
  echo -e "${COLOR_BOOTH:-}> codingbooth $*${COLOR_RESET:-}" >&2
  "$BOOTH_BIN" "$@"
}

NAME="$(generate_name)"
PORT="$(pick_free_port)"

WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth/startups"
cat > "$WORK/.booth/startups/logs-demo--startup.sh" <<'EOF'
#!/bin/bash
echo "logs-demo says hello on stdout"
printf 'svc line 1\nsvc line 2\n' > /tmp/svc.log
echo "alpha" > /tmp/fam-a.log
echo "beta"  > /tmp/fam-b.log
( while true; do echo "tick"; sleep 1; done ) >> /tmp/ticker.log 2>&1 &
EOF
chmod +x "$WORK/.booth/startups/logs-demo--startup.sh"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

run_coding_booth --variant base --code "$WORK" --name "$NAME" --port "$PORT" \
  --daemon --keep-alive --no-browser > "$0.log" 2>&1

# --- Wait for the startup script to have written its logs ---
for i in {1..60}; do
  if docker exec "$NAME" test -f /tmp/ticker.log >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! docker exec "$NAME" test -f /tmp/ticker.log >/dev/null 2>&1; then
  print_test_result "false" "$0" "0" "Booth '$NAME' did not run its startup script"
  exit 1
fi

# -------------------------------------------------------
# Test 1: container output
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" || true)
if [[ "$OUT" == *"logs-demo says hello on stdout"* ]]; then
  print_test_result "true" "$0" "1" "booth logs shows the container output"
else
  print_test_result "false" "$0" "1" "booth logs shows the container output (output below)"
  echo "$OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 2: one service log
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" svc || true)
if [[ "$OUT" == $'svc line 1\nsvc line 2' ]]; then
  print_test_result "true" "$0" "2" "booth logs svc shows /tmp/svc.log"
else
  print_test_result "false" "$0" "2" "booth logs svc (got: $OUT)"
  exit 1
fi

# -------------------------------------------------------
# Test 3: a <name>-*.log family
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" fam || true)
if [[ "$OUT" == *"==> /tmp/fam-a.log <=="*"alpha"*"==> /tmp/fam-b.log <=="*"beta"* ]]; then
  print_test_result "true" "$0" "3" "booth logs fam shows fam-a.log and fam-b.log with headers"
else
  print_test_result "false" "$0" "3" "booth logs fam (output below)"
  echo "$OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 4: --list
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" --list || true)
if echo "$OUT" | grep -qE '^svc[[:space:]].*/tmp/svc\.log$' && \
   echo "$OUT" | grep -qE '^startups[[:space:]]'; then
  print_test_result "true" "$0" "4" "booth logs --list names svc and startups"
else
  print_test_result "false" "$0" "4" "booth logs --list (output below)"
  echo "$OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 5: --startup
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" --startup || true)
if [[ "$OUT" == *"Running startup script:"* ]]; then
  print_test_result "true" "$0" "5" "booth logs --startup shows /tmp/startups.log"
else
  print_test_result "false" "$0" "5" "booth logs --startup (output below)"
  echo "$OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 6: an interrupted follow leaves no tail in the booth
# -------------------------------------------------------
OUT=$(timeout -s INT 3 "$BOOTH_BIN" logs --name "$NAME" ticker -f -n 1 || true)
sleep 2
LEFT=$(docker exec "$NAME" ps -eo args | grep -c '^tail ' || true)
if [[ "$OUT" == *"tick"* && "$LEFT" == "0" ]]; then
  print_test_result "true" "$0" "6" "booth logs -f follows, and Ctrl+C stops the tail in the booth"
else
  print_test_result "false" "$0" "6" "booth logs -f (leftover tails: $LEFT, output: $OUT)"
  exit 1
fi

# -------------------------------------------------------
# Test 7: a stopped booth still has its logs
# -------------------------------------------------------
docker stop "$NAME" >/dev/null 2>&1
OUT_CONTAINER=$(run_booth logs --name "$NAME" || true)
OUT_SVC=$(run_booth logs --name "$NAME" svc -n 1 || true)
if [[ "$OUT_CONTAINER" == *"logs-demo says hello on stdout"* && "$OUT_SVC" == "svc line 2" ]]; then
  print_test_result "true" "$0" "7" "booth logs reads a stopped booth's output and log files"
else
  print_test_result "false" "$0" "7" "stopped booth (container: $OUT_CONTAINER / svc: $OUT_SVC)"
  exit 1
fi
