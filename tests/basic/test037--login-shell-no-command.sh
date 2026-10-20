#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a container started with no command gets coder's login shell.
#
# booth-entry falls back to `booth--as-coder --login` when it is given no
# command. That once ran `runuser -u coder --login`, which util-linux 2.41
# (Ubuntu 26.04) refuses ("--login and --user are mutually exclusive"), so the
# container printed that and exited. The CLI always passes a command, so this
# starts the image with docker directly: the entrypoint, and nothing after it.
#
# The helper under test is bind-mounted over the image's copy, so this checks
# the tree rather than whichever helper the image was built with. With no
# terminal, the login shell reads its commands from stdin.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="login-nocmd-$RANDOM"
LOG="$0.log"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# The tree keeps the helper non-executable; the image build adds +x.
AS_CODER="$WORK/booth--as-coder"
cp "$REPO/variants/base/booth--as-coder" "$AS_CODER"
chmod 755 "$AS_CODER"

IMAGE="nawaman/codingbooth:base-$(get_booth_version)"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "SKIP: $IMAGE is not available locally"
  exit 0
fi

PROBE='echo "WHO=$(whoami)"; echo "LOGIN=$(shopt -q login_shell && echo yes || echo no)"; echo "HOME=$HOME"; exit'

RC=0
printf '%s\n' "$PROBE" | timeout_run 120 docker run --rm -i --name "$NAME" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$AS_CODER:/usr/local/bin/booth--as-coder:ro" \
  --entrypoint tini "$IMAGE" -g -- /usr/local/bin/booth-entry \
  > "$LOG" 2>&1 || RC=$?
OUT="$(tr -d '\r' < "$LOG")"

# -------------------------------------------------------
# Test 1: runuser does not refuse the login.
# -------------------------------------------------------
if [[ "$OUT" != *"mutually exclusive"* ]]; then
  print_test_result "true"  "$0" "1" "No-command start does not trip runuser's --login/--user refusal"
else
  print_test_result "false" "$0" "1" "No-command start should not trip runuser's --login/--user refusal"
  tail -20 "$LOG" >&2
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: the shell is coder's, it is a login shell, and it ran the probe.
# -------------------------------------------------------
if [[ "$RC" -eq 0 && "$OUT" == *"WHO=coder"* && "$OUT" == *"LOGIN=yes"* && "$OUT" == *"HOME=/home/coder"* ]]; then
  print_test_result "true"  "$0" "2" "No-command start runs coder's login shell"
else
  print_test_result "false" "$0" "2" "No-command start should run coder's login shell (rc=$RC)"
  tail -20 "$LOG" >&2
  FAILED=$((FAILED + 1))
fi

exit $FAILED
