#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: booth--gnupg-trust-brought, the helper that makes a key brought
# from the host the user's own
#
# A key whose files are copied into a booth (gnupg+keys, envfolio+seed) has no
# owner trust there -- the host's trust database is not brought -- and gpg will
# not encrypt to an untrusted key without being asked, so `pass insert` and
# `folio secret insert` failed. The helper marks the keys whose private key
# files came (.booth/.tmp/gnupg-keys/private-keys/<keygrip>.key) as ultimately
# trusted, and only those; a key that already has an owner trust keeps it.
#
# The helper is extracted from gnupg--setup.sh and run with the host's real gpg
# on throwaway gpg homes: "booth" imports two keys exported from "host", as a
# booth gets them. Skipped when the host has no gpg.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

if ! command -v gpg >/dev/null 2>&1; then
    echo "⏭️  setups/test--gnupg-trust-brought: gpg is not on the host; skipped"
    exit 0
fi

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/gnupg--setup.sh"

# A short path: gpg's sockets live in the home, and a socket path has a length limit.
WORK=$(mktemp -d /tmp/cbtb.XXXXXX)
cleanup() {
    for h in "$WORK"/host "$WORK"/booth*; do
        [[ -d "$h" ]] && gpgconf --homedir "$h" --kill all >/dev/null 2>&1 || true
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

HELPER="$WORK/booth--gnupg-trust-brought"
awk '/> "\$TRUST_HELPER" <<.EOT.$/{flag=1;next}/^EOT$/{flag=0}flag' "$SETUP_SCRIPT" > "$HELPER"
if ! grep -q 'import-ownertrust' "$HELPER"; then
    echo "❌ Could not extract the trust helper from $SETUP_SCRIPT"
    exit 1
fi

ALL_PASSED=true
TEST_NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    print_test_result "$ok" "$0" "$TEST_NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -12
        ALL_PASSED=false
    fi
}

g() { local home="$1"; shift; gpg --homedir "$home" --batch --quiet "$@"; }
fpr_of()   { g "$1" --with-colons --list-keys "$2" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}'; }
grips_of() { g "$1" --with-colons --with-keygrip --list-secret-keys "$2" 2>/dev/null | awk -F: '/^grp/{print $10}'; }
# trust_of HOME FPR -- the owner trust gpg holds for the key ("" when it has none).
trust_of() { g "$1" --export-ownertrust 2>/dev/null | awk -F: -v f="$2" '$1 == f {print $2}'; }
can_encrypt() { echo x | g "$1" -e -r "$2" >/dev/null 2>&1; }

# The host: two keys, as its gpg made them.
mkdir_private "$WORK/host"
g "$WORK/host" --passphrase '' --quick-generate-key "Mine <mine@example.com>"   default default never 2>/dev/null
g "$WORK/host" --passphrase '' --quick-generate-key "Other <other@example.com>" default default never 2>/dev/null
MINE=$(fpr_of "$WORK/host" mine@example.com)
OTHER=$(fpr_of "$WORK/host" other@example.com)
if [[ -z "$MINE" || -z "$OTHER" ]]; then
    echo "❌ Could not make the throwaway keys in $WORK/host"
    exit 1
fi

# new_booth NAME -- a gpg home holding both keys, imported: neither has an owner trust.
new_booth() {
    mkdir_private "$WORK/$1"
    g "$WORK/host" --armor --export-secret-keys | g "$WORK/$1" --import 2>/dev/null
}
# The folder the CLI writes: the private key files of "mine" only.
KEYS="$WORK/gnupg-keys"
mkdir -p "$KEYS/private-keys"
for grip in $(grips_of "$WORK/host" mine@example.com); do
    : > "$KEYS/private-keys/$grip.key"
done

run_helper() { OUT=$(GNUPGHOME="$1" bash "$HELPER" "$2" 2>&1) && RUN_EXIT=0 || RUN_EXIT=$?; }
OUT="" ; RUN_EXIT=0

# ---- 1. the bug this is for ----
new_booth booth1
! can_encrypt "$WORK/booth1" mine@example.com \
    && check "true"  "before: gpg will not encrypt to a key that was only copied in" \
    || check "false" "before: gpg will not encrypt to a key that was only copied in" "it encrypted; the test no longer shows the problem"

# ---- 2. the brought key becomes the user's own, the other does not ----
run_helper "$WORK/booth1" "$KEYS"
[[ "$RUN_EXIT" -eq 0 && "$(trust_of "$WORK/booth1" "$MINE")" == 6 && -z "$(trust_of "$WORK/booth1" "$OTHER")" ]] \
    && check "true"  "the key whose private files came is ultimately trusted; a key that only sits in the keyring is not" \
    || check "false" "the key whose private files came is ultimately trusted; a key that only sits in the keyring is not" \
         "mine: '$(trust_of "$WORK/booth1" "$MINE")' other: '$(trust_of "$WORK/booth1" "$OTHER")'"$'\n'"$OUT"

can_encrypt "$WORK/booth1" mine@example.com && ! can_encrypt "$WORK/booth1" other@example.com \
    && check "true"  "gpg now encrypts to the brought key without asking, and still not to the other" \
    || check "false" "gpg now encrypts to the brought key without asking, and still not to the other" "$OUT"

[[ "$OUT" == *"trusting 1 key(s) brought from the host"* ]] \
    && check "true"  "the helper says how many keys it trusted" \
    || check "false" "the helper says how many keys it trusted" "$OUT"

# ---- 3. a second start changes nothing and says nothing ----
run_helper "$WORK/booth1" "$KEYS"
[[ "$RUN_EXIT" -eq 0 && -z "$OUT" && "$(trust_of "$WORK/booth1" "$MINE")" == 6 ]] \
    && check "true"  "run again: nothing to do, nothing said" \
    || check "false" "run again: nothing to do, nothing said" "$OUT"

# ---- 4. an owner trust already set (a cached keyring) is kept ----
new_booth booth2
printf '%s:3:\n' "$MINE" | g "$WORK/booth2" --import-ownertrust 2>/dev/null
run_helper "$WORK/booth2" "$KEYS"
[[ "$RUN_EXIT" -eq 0 && "$(trust_of "$WORK/booth2" "$MINE")" == 3 ]] \
    && check "true"  "a key that already has an owner trust keeps it" \
    || check "false" "a key that already has an owner trust keeps it" "mine: '$(trust_of "$WORK/booth2" "$MINE")'"$'\n'"$OUT"

# ---- 5. nothing brought ----
new_booth booth3
run_helper "$WORK/booth3" "$WORK/no-such-dir"
[[ "$RUN_EXIT" -eq 0 && -z "$OUT" && -z "$(trust_of "$WORK/booth3" "$MINE")" ]] \
    && check "true"  "no gnupg-keys/ folder: no key is trusted" \
    || check "false" "no gnupg-keys/ folder: no key is trusted" "$OUT"

$ALL_PASSED
