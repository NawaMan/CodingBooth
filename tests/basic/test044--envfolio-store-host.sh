#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: envfolio+store-host — the host's folio store and gpg home, live in a booth
#
# A throwaway store and gpg home are made on the host (its own GNUPGHOME and
# FOLIO_STORE_DIR, a key with no passphrase so nothing asks), passed to the
# extension as FOLIO_HOST_STORE / FOLIO_HOST_GNUPG. The user's own ~/.folio and
# ~/.gnupg are never touched. In the booth, folio must read what the host wrote
# and write what the host then reads, and gpg-agent must keep its sockets in
# /run/user/<uid>, not in the shared gpg home.
#
# Needs folio and gpg on the host; skipped without them.
# Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if ! command -v folio >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  echo "⏭️  basic/test044: folio or gpg is not on the host; skipped"
  exit 0
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
export GNUPGHOME="$WORK/gnupg" FOLIO_STORE_DIR="$WORK/store"
cleanup() { gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

FAILED=0
fail() { print_test_result "false" "$0" "$1" "$2"; echo "  $3"; FAILED=$((FAILED + 1)); }

# The host side: a key with no passphrase, a store on it, one text and one secret.
mkdir -m 700 "$GNUPGHOME"
if ! { gpg --batch --passphrase '' --quick-gen-key 'Booth Test <booth-test@example.com>' ed25519 sign,cert never \
       && FPR=$(gpg --batch --with-colons --list-secret-keys booth-test@example.com 2>/dev/null | awk -F: '/^fpr/{print $10; exit}') \
       && gpg --batch --passphrase '' --quick-add-key "$FPR" cv25519 encr never \
       && folio init --key "$FPR" \
       && folio text insert -t from-host app/greeting \
       && printf 'host-secret\nhost-secret\n' | folio secret insert app/token; } >/dev/null 2>&1; then
  fail 0 "the throwaway host store is made" "could not make the host store in $WORK"
  exit 1
fi
gpgconf --kill all >/dev/null 2>&1   # the host's agent for this GNUPGHOME: not running while the booth uses it

SCRIPT='
set -e
folio exec --secrets app -- bash -c "echo GOT=\$APP_GREETING/\$APP_TOKEN"
folio text insert -t from-booth app/reply >/dev/null 2>&1
echo SOCKET=$(gpgconf --list-dirs agent-socket)
'
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select "envfolio+store-host:\"$WORK/store\",\"$WORK/gnupg\"" -- "$SCRIPT" 2>&1) || true

# -------------------------------------------------------
# Test 1: the booth reads the host's store with the host's key
# -------------------------------------------------------
if grep -qxF "GOT=from-host/host-secret" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "the booth reads the host's text and decrypts its secret with the host's key"
else
  fail 1 "the booth reads the host's text and decrypts its secret with the host's key" \
    "Output: $(tail -5 <<<"$OUT")"
fi

# -------------------------------------------------------
# Test 2: what the booth writes is in the host's store
# -------------------------------------------------------
REPLY=$(folio text show app/reply 2>/dev/null | tail -1)
if [[ "$REPLY" == "from-booth" ]]; then
  print_test_result "true" "$0" "2" "a text the booth adds is in the host's store, signed with the host's key"
else
  fail 2 "a text the booth adds is in the host's store, signed with the host's key" \
    "folio text show app/reply on the host: ${REPLY:-<nothing>}"
fi

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
# Test 4: every start says the store and keys are live
# -------------------------------------------------------
if grep -qF "Warning: envfolio+store-host: the host's EnvFolio store ($WORK/store)" <<<"$OUT"; then
  print_test_result "true" "$0" "4" "the start warns that the host's store and keys are live in the booth"
else
  fail 4 "the start warns that the host's store and keys are live in the booth" "no warning in the output"
fi

# -------------------------------------------------------
# Test 5: a missing host store stops the start
# -------------------------------------------------------
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select "envfolio+store-host:\"$WORK/no-store\",\"$WORK/gnupg\"" -- true 2>&1) && RC=0 || RC=$?
if [[ "$RC" -ne 0 ]] && grep -qF "the host has no EnvFolio store at $WORK/no-store" <<<"$OUT" && [[ ! -e "$WORK/no-store" ]]; then
  print_test_result "true" "$0" "5" "a missing host store stops the start, and nothing is created on the host"
else
  fail 5 "a missing host store stops the start, and nothing is created on the host" "rc=$RC $(tail -3 <<<"$OUT")"
fi

exit $FAILED
