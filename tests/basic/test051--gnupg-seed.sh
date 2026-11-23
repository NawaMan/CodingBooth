#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: a keyring from the project — gnupg+seed
#
# The project commits a gpg home at .booth/cache-seed/home/coder/.gnupg/. The
# booth's keyring (cached in .booth/cache/) starts as a copy of it, once:
#   first start   -> the seeded key decrypts in the booth, and ~/.gnupg is 0700
#                    although git kept no mode for the seed (files 644, folders 755)
#   second start  -> a key the booth made itself is still there, so the keyring
#                    was kept and the seed was not copied over it
#
# The seed's key is a throwaway with no passphrase, made in the seed folder
# itself (gpg --homedir); the user's own ~/.gnupg is never touched.
# Needs gpg on the host. Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if ! command -v gpg >/dev/null 2>&1; then
  echo "⏭️  basic/test051: gpg is not on the host; skipped"
  exit 0
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
PROJECT="$WORK/project"
SEED="$PROJECT/.booth/cache-seed/home/coder/.gnupg"
NAME="booth-gnupg-seed-$RANDOM"
PORT="$(pick_free_port)"
mkdir -p "$PROJECT"
cleanup() {
  gpgconf --homedir "$WORK/g" --kill all >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # The booth writes the cached keyring as its own user, which may not be this one.
  rm -rf "$WORK" 2>/dev/null || docker run --rm -v "$WORK:/work" busybox rm -rf /work/project >/dev/null 2>&1 || true
  rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

FAILED=0
fail() { print_test_result "false" "$0" "$1" "$2"; echo "  $3"; FAILED=$((FAILED + 1)); }

# The project, as `booth config` makes it: the Cache path declared, the seed folder marked.
CONFIG_OUT=$(CB_TEMPLATES_PATH="$REPO/templates" \
  run_coding_booth config "$PROJECT" --no-tui --select 'gnupg+seed' 2>&1) || true
if [[ ! -f "$SEED/.mount-this" ]]; then
  fail 0 "booth config makes the seed folder" "$(tail -3 <<<"$CONFIG_OUT")"
  exit 1
fi

# The seed's keyring, and a message only its key opens. It is made in a short home and then
# copied in: gpg-agent's socket goes in the home, and on macOS $SEED under $TMPDIR is past the
# 104-byte socket path limit, so the agent would not start there.
KEYGEN="$WORK/g"
mkdir_private "$KEYGEN"
gpg --homedir "$KEYGEN" --batch --quiet --passphrase '' \
    --quick-generate-key "Seed Test <seed@example.com>" default default never >/dev/null 2>&1
echo "seeded-message" | gpg --homedir "$KEYGEN" --batch --quiet --trust-model always \
    -e -r seed@example.com > "$PROJECT/message.gpg" 2>/dev/null
gpgconf --homedir "$KEYGEN" --kill all >/dev/null 2>&1
cp -R "$KEYGEN"/. "$SEED"/
chmod 700 "$SEED"
if [[ ! -s "$PROJECT/message.gpg" ]]; then
  fail 0 "the throwaway seed key is made" "could not make it in $SEED"
  exit 1
fi
# As a clone has it: git keeps no mode, and leaves no socket or lock behind.
find "$SEED" -type s -delete 2>/dev/null
find "$SEED" -name '.#lk*' -delete 2>/dev/null
find "$SEED" -type f -exec chmod 644 {} +
find "$SEED" -type d -exec chmod 755 {} +
# What `booth config` already put in .booth/cache/ is not in a clone either.
rm -rf "$PROJECT/.booth/cache"

secret_count() { sed -n 's/^SECRETS=//p' <<<"$1"; }

# -------------------------------------------------------
# First start: the booth's keyring is the seed's
# -------------------------------------------------------
SCRIPT='
echo MODE=$(stat -c %a ~/.gnupg)
echo GOT=$(gpg --batch --quiet -d ~/code/message.gpg 2>/dev/null)
gpg --batch --quiet --passphrase "" --quick-generate-key "Own <own@example.com>" default default never >/dev/null 2>&1
echo SECRETS=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -c "^sec")
gpgconf --kill all >/dev/null 2>&1
'
OUT=$(run_coding_booth --code "$PROJECT" --name "$NAME" --port "$PORT" -- "$SCRIPT" 2>&1 </dev/null) || true

if grep -qx "GOT=seeded-message" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "gnupg+seed: the key committed in the project decrypts in the booth"
else
  fail 1 "gnupg+seed: the key committed in the project decrypts in the booth" \
    "$(grep -E '^GOT|Seeded|rror' <<<"$OUT" | head -4)"
fi

if ! unix_modes; then
  # ~/.gnupg is cached in the project's .booth/cache: a host folder, and a Windows one keeps no mode.
  echo "SKIP: test 2: the cached keyring is in a host folder, and this host keeps no modes"
elif grep -qx "MODE=700" <<<"$OUT"; then
  print_test_result "true" "$0" "2" "the seeded keyring is 0700, though the seed's folder was not"
else
  fail 2 "the seeded keyring is 0700, though the seed's folder was not" "$(grep '^MODE' <<<"$OUT")"
fi

if grep -qF "Seeded .booth/cache/home/coder/.gnupg from .booth/cache-seed/" <<<"$OUT"; then
  print_test_result "true" "$0" "3" "the start says the keyring was seeded"
else
  fail 3 "the start says the keyring was seeded" "$(grep -i 'seed' <<<"$OUT" | head -3)"
fi

# -------------------------------------------------------
# Second start: the keyring is the booth's own now
# -------------------------------------------------------
docker rm -f "$NAME" >/dev/null 2>&1 || true
SCRIPT='
echo GOT=$(gpg --batch --quiet -d ~/code/message.gpg 2>/dev/null)
echo SECRETS=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -c "^sec")
gpgconf --kill all >/dev/null 2>&1
'
OUT2=$(run_coding_booth --code "$PROJECT" --name "$NAME" --port "$PORT" -- "$SCRIPT" 2>&1 </dev/null) || true

if [[ "$(secret_count "$OUT")" == "2" && "$(secret_count "$OUT2")" == "2" ]] && grep -qx "GOT=seeded-message" <<<"$OUT2"; then
  print_test_result "true" "$0" "4" "a new container keeps the keyring: the seeded key and the one the booth made"
else
  fail 4 "a new container keeps the keyring: the seeded key and the one the booth made" \
    "secret keys: first start ${OUT:+$(secret_count "$OUT")}, second ${OUT2:+$(secret_count "$OUT2")}; $(grep -E '^GOT|rror' <<<"$OUT2" | head -2)"
fi

if ! grep -qF "Seeded .booth/cache/" <<<"$OUT2"; then
  print_test_result "true" "$0" "5" "the seed is not copied over a keyring that is already there"
else
  fail 5 "the seed is not copied over a keyring that is already there" "$(grep -F 'Seeded' <<<"$OUT2" | head -2)"
fi

exit $FAILED
