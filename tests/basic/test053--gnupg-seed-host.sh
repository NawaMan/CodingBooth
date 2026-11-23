#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: gnupg+seed-host — the booth's keyring starts as a copy of the host's
#
# A throwaway gpg home is made on the host (a key with no passphrase so nothing
# asks) and passed to the extension as GNUPG_SEED_HOME. The user's own ~/.gnupg
# is never touched. In the booth, gpg must have the host's key with the host's
# trust in it (it decrypts, and encrypts without asking), and what the booth
# then does to its keyring must not reach the host: that is the whole
# difference from gnupg+store-host (test052).
#
# The same again for a host keyring kept by keyboxd (use-keyboxd, the default
# for a new home since GnuPG 2.4.1): its public keys are in a database, not in
# pubring.kbx. Skipped when the host's gpg cannot make one.
#
# Needs gpg on the host, and a base image whose gnupg startup hook copies the
# keyring (gnupg--setup.sh 0.6.0+).
# Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if ! command -v gpg >/dev/null 2>&1; then
  echo "⏭️  basic/test053: gpg is not on the host; skipped"
  exit 0
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
HWORK="$(host_path "$WORK")"   # as booth is handed it: C:/… on Windows
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
cleanup() {
  for h in "$WORK"/gnupg "$WORK"/gnupg-kbxd; do
    [[ -d "$h" ]] && gpgconf --homedir "$h" --kill all >/dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

FAILED=0
fail() { print_test_result "false" "$0" "$1" "$2"; echo "  $3"; FAILED=$((FAILED + 1)); }

# make_host HOME NAME -- a key with no passphrase, and a message only it opens.
make_host() {
  gpg --homedir "$1" --batch --quiet --passphrase '' \
      --quick-generate-key 'Host <host@example.com>' default default never >/dev/null 2>&1 || return 1
  echo "from-host" | gpg --homedir "$1" --batch --quiet -e -r host@example.com > "$PROJECT/$2.gpg" 2>/dev/null
  gpgconf --homedir "$1" --kill all >/dev/null 2>&1   # nothing of the host's is running while the booth copies
  [[ -s "$PROJECT/$2.gpg" ]]
}
# What the host's gpg home holds: every file, with its content.
snapshot() { (cd "$1" && find . -type f ! -name 'random_seed' ! -name '*.lock' ! -name '.#lk*' -exec sha256sum {} + | LC_ALL=C sort); }

SCRIPT='
echo GOT=$(gpg --batch --quiet -d ~/code/$MSG.gpg 2>/dev/null)
echo x | gpg --batch -e -r host@example.com >/dev/null 2>&1 && echo ENC=ok || echo ENC=refused
gpg --batch --quiet --passphrase "" --quick-generate-key "Booth <booth@example.com>" default default never >/dev/null 2>&1
echo SECRETS=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -c "^sec")
gpgconf --kill all >/dev/null 2>&1
'
run_seeded() { # run_seeded HOSTHOME MSG
  run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
    --select "gnupg+seed-host:\"$(host_path "$1")\"" -- "MSG=$2; $SCRIPT" 2>&1 </dev/null || true
}

mkdir_private "$WORK/gnupg"
if ! make_host "$WORK/gnupg" plain; then
  fail 0 "the throwaway host key is made" "could not make it in $WORK/gnupg"
  exit 1
fi
BEFORE=$(snapshot "$WORK/gnupg")
OUT=$(run_seeded "$WORK/gnupg" plain)

# -------------------------------------------------------
# Test 1: the booth has the host's key, and the host's trust in it
# -------------------------------------------------------
if grep -qx "GOT=from-host" <<<"$OUT" && grep -qx "ENC=ok" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "the booth decrypts with the host's key, and encrypts to it without asking"
else
  fail 1 "the booth decrypts with the host's key, and encrypts to it without asking" \
    "$(grep -E '^GOT|^ENC|rror|GnuPG keys' <<<"$OUT" | tr '\n' ' ')"
fi

# -------------------------------------------------------
# Test 2: the keyring is the booth's own, and the host's is as it was
# -------------------------------------------------------
AFTER=$(snapshot "$WORK/gnupg")
if grep -qx "SECRETS=2" <<<"$OUT" && [[ "$BEFORE" == "$AFTER" ]] \
   && ! gpg --homedir "$WORK/gnupg" --batch --list-keys booth@example.com >/dev/null 2>&1; then
  print_test_result "true" "$0" "2" "a key the booth makes stays in the booth: the host's gpg home is unchanged"
else
  fail 2 "a key the booth makes stays in the booth: the host's gpg home is unchanged" \
    "$(grep '^SECRETS' <<<"$OUT"); host changed: $([[ "$BEFORE" == "$AFTER" ]] && echo no || echo yes)"
fi
gpgconf --homedir "$WORK/gnupg" --kill all >/dev/null 2>&1

# -------------------------------------------------------
# Test 3: every start says the keys came, and it is not a writable host mount
# (The hook's own line goes to the booth's /tmp/startups.log, not here; the
# setups test for the hook covers it.)
# -------------------------------------------------------
if grep -qF "Warning: gnupg+seed-host: the host's gpg keyring ($HWORK/gnupg), private keys included" <<<"$OUT" \
   && ! grep -qF "writable mount of host" <<<"$OUT"; then
  print_test_result "true" "$0" "3" "the start warns that the host's keys are copied in, and asks no consent for a writable mount"
else
  fail 3 "the start warns that the host's keys are copied in, and asks no consent for a writable mount" \
    "$(grep -E 'seed-host|GnuPG keys|writable' <<<"$OUT" | cut -c1-160 | head -4)"
fi

# -------------------------------------------------------
# Test 4: a missing host gpg home stops the start
# -------------------------------------------------------
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select "gnupg+seed-host:\"$HWORK/no-gnupg\"" -- true 2>&1) && RC=0 || RC=$?
if [[ "$RC" -ne 0 ]] && grep -qF "the host has no gpg home at $HWORK/no-gnupg" <<<"$OUT" && [[ ! -e "$WORK/no-gnupg" ]]; then
  print_test_result "true" "$0" "4" "a missing host gpg home stops the start, and nothing is created on the host"
else
  fail 4 "a missing host gpg home stops the start, and nothing is created on the host" "rc=$RC $(tail -3 <<<"$OUT")"
fi

# -------------------------------------------------------
# Test 5: a host keyring kept by keyboxd
# -------------------------------------------------------
mkdir_private "$WORK/gnupg-kbxd"
echo "use-keyboxd" > "$WORK/gnupg-kbxd/common.conf"
if ! make_host "$WORK/gnupg-kbxd" kbxd || [[ ! -f "$WORK/gnupg-kbxd/public-keys.d/pubring.db" ]]; then
  echo "⏭️  basic/test053: Test 5 skipped — the host's gpg cannot keep a keyring with keyboxd"
  exit $FAILED
fi
OUT=$(run_seeded "$WORK/gnupg-kbxd" kbxd)
if grep -qx "GOT=from-host" <<<"$OUT" && grep -qx "ENC=ok" <<<"$OUT" && grep -qx "SECRETS=2" <<<"$OUT"; then
  print_test_result "true" "$0" "5" "a host keyring kept by keyboxd is copied too: its key decrypts and encrypts in the booth"
else
  fail 5 "a host keyring kept by keyboxd is copied too: its key decrypts and encrypts in the booth" \
    "$(grep -E '^GOT|^ENC|^SECRETS|rror|GnuPG keys' <<<"$OUT" | tr '\n' ' ')"
fi

exit $FAILED
