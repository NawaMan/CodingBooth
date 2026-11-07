#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: keys from the host — gnupg+keys, and the store key envfolio+seed brings
#
# A throwaway gpg home on the host (its own GNUPGHOME; keys with no passphrase
# so nothing asks) holds two keys: "named", which the booth is given, and
# "other", which it is not. The user's own ~/.gnupg is never touched.
#   gnupg+keys:"named"   -> named's private key and every public key, not other's private key
#   envfolio+seed        -> the store's items and its key: a secret opens in the booth
#
# Needs gpg (and folio, for the seed case) on the host, and a base image with
# the gnupg startup hook (gnupg--setup.sh 0.3.0+).
# Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if ! command -v folio >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  echo "⏭️  basic/test043: folio or gpg is not on the host; skipped"
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

newkey() { # newkey <email> -> prints the fingerprint
  gpg --batch --passphrase '' --quick-gen-key "Booth Test <$1>" ed25519 sign,cert never >/dev/null 2>&1 || return 1
  local fpr
  fpr=$(gpg --batch --with-colons --list-secret-keys "$1" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
  gpg --batch --passphrase '' --quick-add-key "$fpr" cv25519 encr never >/dev/null 2>&1 || return 1
  echo "$fpr"
}

mkdir -m 700 "$GNUPGHOME"
NAMED=$(newkey named@example.com) && OTHER=$(newkey other@example.com) \
  && { folio init --key "$NAMED" && printf 'seeded-secret\nseeded-secret\n' | folio secret insert app/token; } >/dev/null 2>&1
if [[ -z "${NAMED:-}" || -z "${OTHER:-}" || ! -f "$WORK/store/app/token.gpg" ]]; then
  fail 0 "the throwaway host keys and store are made" "could not make them in $WORK"
  exit 1
fi
gpgconf --kill all >/dev/null 2>&1

# -------------------------------------------------------
# gnupg+keys:"named@example.com"
# -------------------------------------------------------
SCRIPT='
echo SECRET=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: "/^fpr/{print \$10}" | tr "\n" " ")
echo PUBLIC=$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: "/^pub/{getline; print \$10}" | tr "\n" " ")
echo signed | gpg --batch --pinentry-mode loopback --passphrase "" -u named@example.com --clearsign >/dev/null 2>&1 && echo SIGN=ok
'
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select 'gnupg+keys:"named@example.com"' -- "$SCRIPT" 2>&1) || true

SECRET=$(sed -n 's/^SECRET=//p' <<<"$OUT")
if [[ "$SECRET" == *"$NAMED"* && "$SECRET" != *"$OTHER"* ]] && grep -qx "SIGN=ok" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "gnupg+keys brings the named private key (it signs), and not the other one"
else
  fail 1 "gnupg+keys brings the named private key (it signs), and not the other one" \
    "secret keys in the booth: ${SECRET:-none}; $(grep -E '^SIGN|rror' <<<"$OUT" | head -3)"
fi

PUBLIC=$(sed -n 's/^PUBLIC=//p' <<<"$OUT")
if [[ "$PUBLIC" == *"$NAMED"* && "$PUBLIC" == *"$OTHER"* ]]; then
  print_test_result "true" "$0" "2" "gnupg+keys brings the host's whole public keyring"
else
  fail 2 "gnupg+keys brings the host's whole public keyring" "public keys in the booth: ${PUBLIC:-none}"
fi

if grep -qF "Info: GnuPG keys: 2 private key file(s) for named@example.com" <<<"$OUT"; then
  print_test_result "true" "$0" "3" "the start says which keys came (the primary key and its subkey)"
else
  fail 3 "the start says which keys came (the primary key and its subkey)" "$(grep -i 'gnupg' <<<"$OUT" | head -3)"
fi

# -------------------------------------------------------
# envfolio+seed: the store key comes with the items
# -------------------------------------------------------
SCRIPT='
folio exec --secrets app -- bash -c "echo GOT=\$APP_TOKEN" 2>&1
echo SECRET=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: "/^fpr/{print \$10}" | tr "\n" " ")
'
OUT=$(run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
  --select 'envfolio+seed:"--secrets app"' -- "$SCRIPT" 2>&1) || true

SECRET=$(sed -n 's/^SECRET=//p' <<<"$OUT")
if grep -qx "GOT=seeded-secret" <<<"$OUT" && [[ "$SECRET" != *"$OTHER"* ]]; then
  print_test_result "true" "$0" "4" "envfolio+seed brings the store key: the seeded secret opens in the booth, no other key comes"
else
  fail 4 "envfolio+seed brings the store key: the seeded secret opens in the booth, no other key comes" \
    "$(grep -E '^GOT|rror|seed' <<<"$OUT" | head -4); secret keys: ${SECRET:-none}"
fi

exit $FAILED
