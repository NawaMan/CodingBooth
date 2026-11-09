#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the gnupg startup hook that brings keys from the host into the booth
#
# gnupg+keys (the keys a user names) and envfolio+seed (the store key) have the
# CLI copy private key files, as the host's gpg keeps them (<keygrip>.key, still
# passphrase-protected), into .booth/.tmp/gnupg-keys/private-keys/; gnupg+keys
# also writes the host's public keyring to pubkeys.asc. This hook, run at each
# start, puts the key files into ~/.gnupg/private-keys-v1.d (700/600), never over
# one already there, and imports pubkeys.asc.
#
# The hook is extracted from gnupg--setup.sh and run with a stub gpg that records
# the import.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/gnupg--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

HOOK="$WORK/gnupg-keys--startup.sh"
awk '/> "\$STARTUP_FILE" <<.EOF.$/{flag=1;next}/^EOF$/{flag=0}flag' "$SETUP_SCRIPT" > "$HOOK"
if ! grep -q 'CB_GNUPG_KEYS_DIR' "$HOOK"; then
    echo "❌ Could not extract the startup hook from $SETUP_SCRIPT"
    exit 1
fi

mkdir -p "$WORK/bin"
printf '#!/bin/sh\necho "gpg $*" >> "%s/gpg.log"\n' "$WORK" > "$WORK/bin/gpg"
chmod +x "$WORK/bin/gpg"

mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }
GRIP1=E46C9395D7426A1C84DB57D6CD874C312A280EBF
GRIP2=C57CA7B533407125984D2402DCA0A0D36B819A9D

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

# run_hook HOME KEYS_DIR -- the hook in a clean environment; its output is in $OUT.
OUT="" ; RUN_EXIT=0
run_hook() {
    mkdir -p "$1"
    : > "$WORK/gpg.log"
    OUT=$(env -i HOME="$1" PATH="$WORK/bin:/usr/bin:/bin" CB_GNUPG_KEYS_DIR="$2" bash "$HOOK" 2>&1) \
        && RUN_EXIT=0 || RUN_EXIT=$?
}

# ---- 1. nothing brought ----
run_hook "$WORK/h1" "$WORK/no-such-dir"
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/h1/.gnupg" && ! -s "$WORK/gpg.log" ]] \
    && check "true"  "no gnupg-keys/ folder: the gpg home is left alone" \
    || check "false" "no gnupg-keys/ folder: the gpg home is left alone" "$OUT"

# ---- 2. private keys and the public keyring (gnupg+keys) ----
K2="$WORK/keys2"
mk "$K2/private-keys/$GRIP1.key" "protected-primary"
mk "$K2/private-keys/$GRIP2.key" "protected-sub"
mk "$K2/pubkeys.asc"             "PUBLIC KEYRING"
chmod 644 "$K2/private-keys/"*.key
run_hook "$WORK/h2" "$K2"
P="$WORK/h2/.gnupg/private-keys-v1.d"
[[ "$RUN_EXIT" -eq 0 && "$(cat "$P/$GRIP1.key")" == protected-primary && "$(cat "$P/$GRIP2.key")" == protected-sub \
   && "$(file_mode "$P/$GRIP1.key")" == 600 && "$(file_mode "$P")" == 700 \
   && "$(file_mode "$WORK/h2/.gnupg")" == 700 ]] \
    && check "true"  "the key files go to ~/.gnupg/private-keys-v1.d as they are, 600 in 700 folders" \
    || check "false" "the key files go to ~/.gnupg/private-keys-v1.d as they are, 600 in 700 folders" "$(ls -laR "$WORK/h2/.gnupg" 2>&1)"$'\n'"$OUT"

grep -qF "gpg --batch --quiet --import $K2/pubkeys.asc" "$WORK/gpg.log" \
  && grep -qF "brought 2 private key file(s)" <<<"$OUT" \
    && check "true"  "the public keyring is imported, and the hook says how many keys came" \
    || check "false" "the public keyring is imported, and the hook says how many keys came" "$(cat "$WORK/gpg.log")"$'\n'"$OUT"

# ---- 3. a key file already there is kept ----
mkdir -p "$WORK/h3/.gnupg/private-keys-v1.d"
echo "already-here" > "$WORK/h3/.gnupg/private-keys-v1.d/$GRIP2.key"
run_hook "$WORK/h3" "$K2"
[[ "$RUN_EXIT" -eq 0 && "$(cat "$WORK/h3/.gnupg/private-keys-v1.d/$GRIP2.key")" == already-here \
   && -f "$WORK/h3/.gnupg/private-keys-v1.d/$GRIP1.key" && "$OUT" == *"brought 1 private key file(s)"* ]] \
    && check "true"  "a key file already in the booth is never replaced" \
    || check "false" "a key file already in the booth is never replaced" "$OUT"

# ---- 4. a store key only (envfolio+seed): no public keyring to import ----
K4="$WORK/keys4"
mk "$K4/private-keys/$GRIP1.key" "protected-primary"
run_hook "$WORK/h4" "$K4"
[[ "$RUN_EXIT" -eq 0 && -f "$WORK/h4/.gnupg/private-keys-v1.d/$GRIP1.key" && ! -s "$WORK/gpg.log" ]] \
    && check "true"  "key files without pubkeys.asc: copied, and gpg is not run" \
    || check "false" "key files without pubkeys.asc: copied, and gpg is not run" "$(cat "$WORK/gpg.log")"$'\n'"$OUT"

$ALL_PASSED
