#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: envfolio (EnvFolio) ships in the base image
#
# envfolio is installed by variants/base/setups/envfolio--setup.sh from the
# Dockerfile, together with pass, so every variant inherits it. It is also
# advertised in the login welcome message.
#
# Deliberately NOT `set -e`: see test016--viewmd.sh — a booth that fails to
# start makes every capture empty, and each check reports what it got instead.
# -------------------------------------------------------

FAILED=0

# -------------------------------------------------------
# Test 1: envfolio and pass are on PATH
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'command -v envfolio pass | tr "\n" " "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "/usr/local/bin/envfolio /usr/bin/pass " ]]; then
  print_test_result "true" "$0" "1" "envfolio and pass are installed in the base image"
else
  print_test_result "false" "$0" "1" "envfolio and pass are installed in the base image"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  echo "  Hint: the base image must carry envfolio. If a locally-built image has"
  echo "        taken the ${CB_PREBUILD_REPO:-nawaman/codingbooth} tag, re-pull it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: envfolio runs and reports a version
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'envfolio version' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" =~ ^EnvFolio\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
  print_test_result "true" "$0" "2" "envfolio reports a version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "envfolio reports a version"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome message lists envfolio
# (see test016 for why the inner `bash -lic` prints the banner)
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'bash -lic true 2>/dev/null | grep -c "^  envfolio "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome message lists envfolio"
else
  print_test_result "false" "$0" "3" "welcome message lists envfolio"
  echo "  Matching welcome lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: envfolio does what a user does with it first
#
# Make a store, add a text and a secret, and load both into a command's
# environment. Signing a text and decrypting a secret ask gpg for the key's
# passphrase; a user types it into pinentry, and this test (no terminal) hands
# it to gpg through loopback instead.
# -------------------------------------------------------
SCRIPT='
set -e
PW=booth-test-passphrase
printf "%s\n" "$PW" | envfolio store init --new-key --name Test --email test@example.com --passphrase-stdin >/dev/null 2>&1
printf "%s\n" "$PW" > /tmp/ef-pw
printf "pinentry-mode loopback\npassphrase-file /tmp/ef-pw\n" >> ~/.gnupg/gpg.conf
envfolio text insert -t hello-text app/greeting >/dev/null 2>&1
printf "s3cret\ns3cret\n" | envfolio secret insert app/token >/dev/null 2>&1
envfolio text show app/greeting >/dev/null
envfolio exec --secrets app -- bash -c "echo GOT=\$APP_GREETING/\$APP_TOKEN"
'
ACTUAL=$(run_coding_booth --variant base -- "$SCRIPT" 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "GOT=hello-text/s3cret" ]]; then
  print_test_result "true" "$0" "4" "envfolio stores a text and a secret and loads them as env vars"
else
  print_test_result "false" "$0" "4" "envfolio stores a text and a secret and loads them as env vars"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>} (want GOT=hello-text/s3cret)"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
