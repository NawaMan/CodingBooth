#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: gnupg+store-host — the host's gpg home, live in a booth, with no EnvFolio store
#
# A throwaway gpg home is made on the host (a key with no passphrase so nothing
# asks) and passed to the extension as GNUPG_HOST_HOME. The user's own ~/.gnupg
# is never touched. In the booth, gpg must have the host's key with the host's
# trust in it (so it decrypts, and encrypts without asking), a key the booth
# makes must be on the host afterwards, and gpg-agent must keep its sockets in
# /run/user/<uid>, not in the shared gpg home.
#
# Needs gpg on the host; skipped without it.
# Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if ! command -v gpg >/dev/null 2>&1; then
  echo "⏭️  basic/test052: gpg is not on the host; skipped"
  exit 0
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
HWORK="$(host_path "$WORK")"   # as booth is handed it: C:/… on Windows
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
export GNUPGHOME="$WORK/gnupg"
cleanup() { gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

FAILED=0
fail() { print_test_result "false" "$0" "$1" "$2"; echo "  $3"; FAILED=$((FAILED + 1)); }

# The host side: a key with no passphrase, and a message only it opens.
mkdir_private "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-generate-key 'Host <host@example.com>' default default never >/dev/null 2>&1
echo "from-host" | gpg --batch --quiet -e -r host@example.com > "$PROJECT/message.gpg" 2>/dev/null
if [[ ! -s "$PROJECT/message.gpg" ]]; then
  fail 0 "the throwaway host key is made" "could not make it in $WORK/gnupg"
  exit 1
fi
gpgconf --kill all >/dev/null 2>&1   # the host's agent for this GNUPGHOME: not running while the booth uses it

SCRIPT='
echo GOT=$(gpg --batch --quiet -d ~/code/message.gpg 2>/dev/null)
echo x | gpg --batch -e -r host@example.com >/dev/null 2>&1 && echo ENC=ok || echo ENC=refused
gpg --batch --quiet --passphrase "" --quick-generate-key "Booth <booth@example.com>" default default never >/dev/null 2>&1
echo SOCKET=$(gpgconf --list-dirs agent-socket)
gpgconf --kill all >/dev/null 2>&1
'
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select "gnupg+store-host:\"$HWORK/gnupg\"" -- "$SCRIPT" 2>&1) || true

# -------------------------------------------------------
# Test 1: the booth has the host's key, and the host's trust in it
# -------------------------------------------------------
if grep -qx "GOT=from-host" <<<"$OUT" && grep -qx "ENC=ok" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "the booth decrypts with the host's key, and encrypts to it without asking"
else
  fail 1 "the booth decrypts with the host's key, and encrypts to it without asking" \
    "$(grep -E '^GOT|^ENC|rror' <<<"$OUT" | tr '\n' ' ')"
fi

# -------------------------------------------------------
# Test 2: what the booth changes is changed on the host
# -------------------------------------------------------
if gpg --batch --list-secret-keys booth@example.com >/dev/null 2>&1; then
  print_test_result "true" "$0" "2" "a key the booth makes is in the host's keyring"
else
  fail 2 "a key the booth makes is in the host's keyring" \
    "secret keys on the host: $(gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -c '^sec')"
fi
gpgconf --kill all >/dev/null 2>&1

# -------------------------------------------------------
# Test 3: gpg-agent's sockets stay out of the shared gpg home
# -------------------------------------------------------
LEFT=$(find "$GNUPGHOME" -maxdepth 1 -name 'S.*' 2>/dev/null)
if grep -qE "^SOCKET=/run/user/[0-9]+/gnupg/" <<<"$OUT" && [[ -z "$LEFT" ]]; then
  print_test_result "true" "$0" "3" "the booth's gpg-agent sockets are in /run/user/<uid>, none in the host's gpg home"
else
  fail 3 "the booth's gpg-agent sockets are in /run/user/<uid>, none in the host's gpg home" \
    "$(grep '^SOCKET=' <<<"$OUT"); left in the gpg home: ${LEFT:-none}"
fi

# -------------------------------------------------------
# Test 4: every start says the keys are live
# -------------------------------------------------------
if grep -qF "Warning: gnupg+store-host: the host's gpg home ($HWORK/gnupg), private keys included, is live in this booth" <<<"$OUT"; then
  print_test_result "true" "$0" "4" "the start warns that the host's keys are live in the booth"
else
  fail 4 "the start warns that the host's keys are live in the booth" "no warning in the output"
fi

# -------------------------------------------------------
# Test 5: a missing host gpg home stops the start
# -------------------------------------------------------
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select "gnupg+store-host:\"$HWORK/no-gnupg\"" -- true 2>&1) && RC=0 || RC=$?
if [[ "$RC" -ne 0 ]] && grep -qF "the host has no gpg home at $HWORK/no-gnupg" <<<"$OUT" && [[ ! -e "$WORK/no-gnupg" ]]; then
  print_test_result "true" "$0" "5" "a missing host gpg home stops the start, and nothing is created on the host"
else
  fail 5 "a missing host gpg home stops the start, and nothing is created on the host" "rc=$RC $(tail -3 <<<"$OUT")"
fi

exit $FAILED
