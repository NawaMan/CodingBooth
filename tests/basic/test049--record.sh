#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `booth --record` keeps the session on the host, in .booth/.tmp/record/.
#
# One daemon booth, one tmux pane (what a Console UI pane is) with commands typed
# into it, then the booth is stopped and the record is read from the host:
#
#   1. the recorder starts at boot                         (record-started)
#   2. a typed command is logged before it runs            (cmd ... -- <command>)
#   3. its exit status is logged when it returns           (cmd-done exit=3)
#   4. a port that starts listening is logged, with its process  (port-listen)
#   5. a changed file is committed to the shadow repository      (snapshot)
#   6. the pane's output is in an asciicast file                 (terminal/*.cast)
#   7. `booth logs activity` reads it, and the host's own line is there
#      after the booth is gone                                   (stop-requested)
#   8. the project's own folder has no trace of the shadow repository
#
# The scripts under test are bind-mounted over the image's, so this checks the
# tree rather than whichever recorder the image was built with.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="record-$RANDOM"
PORT="$(pick_free_port)"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
ACTIVITY="$WORK/.booth/.tmp/record/activity.log"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/.booth"
echo 'first line' > "$WORK/notes.txt"
SETUPS="$REPO/variants/base/setups"
cat > "$WORK/.booth/config.toml" <<TOML
variant = "base"
run-args = [
  "-v", "$SETUPS/booth--record:/opt/codingbooth/setups/booth--record:ro",
  "-v", "$SETUPS/booth--record-cast:/opt/codingbooth/setups/booth--record-cast:ro",
  "-v", "$SETUPS/booth--lifecycle-log:/opt/codingbooth/setups/booth--lifecycle-log:ro",
  "-v", "$REPO/variants/base/99z-cb--profile.sh:/etc/profile.d/99z-cb--profile.sh:ro",
]
TOML

# wait_for <seconds> <grep pattern> : until the activity log has a matching line.
wait_for() {
  local deadline=$((SECONDS + $1))
  while (( SECONDS < deadline )); do
    grep -qE -- "$2" "$ACTIVITY" 2>/dev/null && return 0
    sleep 0.5
  done
  return 1
}

check() {
  local num="$1" desc="$2" pattern="$3" seconds="${4:-20}"
  if wait_for "$seconds" "$pattern"; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc (no line matching: $pattern)"
    cat "$ACTIVITY" 2>/dev/null >&2 || echo "  (no activity log)" >&2
    FAILED=$((FAILED + 1))
  fi
}

in_pane() { docker exec -u coder "$NAME" tmux send-keys -t rec "$1" Enter; }

run_coding_booth --code "$WORK" --name "$NAME" --port "$PORT" --daemon --no-browser --record \
  --env BOOTH_RECORD_SNAPSHOT_INTERVAL=2 > "$0.log" 2>&1 || true

check 1 "The recorder starts when a --record booth boots" ' record-started ' 60

docker exec -u coder "$NAME" tmux new-session -d -s rec -x 100 -y 30 >/dev/null 2>&1 || true
check 6a "A tmux pane starts being recorded" ' terminal-recording pane=rec:' 20

in_pane 'echo RECORD-MARKER-ONE; (exit 3)'
check 2 "A typed command is logged, with its text" ' cmd shell=bash .* -- echo RECORD-MARKER-ONE; \(exit 3\)$'
check 3 "The command's exit status is logged when it returns" ' cmd-done pid=[0-9]+ exit=3 '

in_pane 'echo second line >> notes.txt'
check 5 "A changed file is committed to the shadow repository" ' snapshot commit=[0-9a-f]+ changed:.*files=notes.txt'

in_pane 'perl -MIO::Socket::INET -e "my \$s = IO::Socket::INET->new(Listen => 1, LocalPort => 3456, ReuseAddr => 1) or die; sleep 30"'
check 4 "A port that starts listening is logged, with its process" ' port-listen port=3456 .* proc=perl '

# -------------------------------------------------------
# Test 6: the pane's output is in the asciicast file.
# -------------------------------------------------------
CAST="$(ls "$WORK"/.booth/.tmp/record/terminal/rec-*.cast 2>/dev/null | head -1)"
if [[ -n "$CAST" ]] && head -1 "$CAST" | grep -q '"version":2' && grep -q 'RECORD-MARKER-ONE' "$CAST"; then
  print_test_result "true"  "$0" "6" "The pane's output is recorded as asciicast v2"
else
  print_test_result "false" "$0" "6" "The pane's output should be in an asciicast v2 file, got '${CAST:-no file}'"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 7: read from the host, after the booth is gone.
# -------------------------------------------------------
run_coding_booth stop --name "$NAME" >> "$0.log" 2>&1 || true
READ="$(run_coding_booth logs --code "$WORK" activity 2>&1 || true)"
if [[ "$READ" == *" record-started "* && "$READ" == *" stop-requested by=host-cli"* ]]; then
  print_test_result "true"  "$0" "7" "booth logs activity reads the session after the booth is stopped, with the host's stop line"
else
  print_test_result "false" "$0" "7" "booth logs activity should show the session and the host's stop line"
  echo "$READ" | tail -15 >&2
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 8: the shadow repository is not the project's.
# -------------------------------------------------------
if [[ ! -e "$WORK/.git" ]] && \
   [[ "$(git --git-dir="$WORK/.booth/.tmp/record/snapshots.git" rev-list --count HEAD 2>/dev/null || echo 0)" -ge 2 ]]; then
  print_test_result "true"  "$0" "8" "Snapshots are in their own repository; the code folder gets no .git"
else
  print_test_result "false" "$0" "8" "Snapshots should be in .booth/.tmp/record/snapshots.git only, with a baseline and a change"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
