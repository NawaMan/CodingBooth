#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the envfolio startup hook that makes the booth's store from a seed
#
# envfolio+seed has the CLI copy chosen items of the host's store, still
# encrypted, into .booth/.tmp/folio-seed/ (with .gpg-id and pubkey.asc). This
# hook, run at each start, makes that the booth's store:
#   seed (default) -- only when there is no store; an existing one is kept.
#   fill           -- also adds what an existing store lacks, when it has the
#                     same key; never replaces an item, never mixes keys.
#
# envfolio+agent mounts the host gpg-agent's extra socket at CB_GPG_AGENT_SOCK;
# the hook points gpg at it with an Assuan redirect file at gpg's own socket path,
# and no-autostart, so the booth decrypts with the host key and never holds it.
#
# The hook is extracted from envfolio--setup.sh and run with a stub folio (for
# `folio path`), gpg (records the import) and gpgconf; git is real.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/envfolio--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

HOOK="$WORK/envfolio--startup.sh"
awk '/> "\$STARTUP_FILE" <<.EOF.$/{flag=1;next}/^EOF$/{flag=0}flag' "$SETUP_SCRIPT" > "$HOOK"
if ! grep -q 'CB_FOLIO_SEED' "$HOOK"; then
    echo "❌ Could not extract the startup hook from $SETUP_SCRIPT"
    exit 1
fi

mkdir -p "$WORK/bin"
printf '#!/bin/sh\n[ "$1" = path ] && echo "${FOLIO_STORE_DIR:-$HOME/.folio}"\n' > "$WORK/bin/folio"
printf '#!/bin/sh\necho "gpg $*" >> "%s/gpg.log"\n' "$WORK" > "$WORK/bin/gpg"
printf '#!/bin/sh\n[ "$1" = --list-dirs ] && echo "$HOME/.gnupg/S.gpg-agent"\nexit 0\n' > "$WORK/bin/gpgconf"
chmod +x "$WORK/bin/folio" "$WORK/bin/gpg" "$WORK/bin/gpgconf"
GIT_BIN_DIR="$(dirname "$(command -v git)")"

# The seed, as the CLI writes it.
SEED="$WORK/seed"
mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }
mk "$SEED/.gpg-id"                         "HOSTKEY"$'\n'
mk "$SEED/.gitattributes"                  "*.gpg diff=gpg"$'\n'
mk "$SEED/pubkey.asc"                      "PUBLIC KEY"
mk "$SEED/gh/user.txt"                     "other"
mk "$SEED/gh/user.txt.sig"                 "sig-host"
mk "$SEED/@app2/@prod/server/password.gpg" "enc-host"

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

# run_hook HOME [VAR=value…] -- the hook in a clean environment; its output is in $OUT.
OUT="" ; RUN_EXIT=0
run_hook() {
    local home="$1"; shift
    mkdir -p "$home"
    : > "$WORK/gpg.log"
    OUT=$(env -i HOME="$home" PATH="$WORK/bin:$GIT_BIN_DIR:/usr/bin:/bin" CB_FOLIO_SEED_DIR="$SEED" "$@" \
        bash "$HOOK" 2>&1) && RUN_EXIT=0 || RUN_EXIT=$?
}
files() { (cd "$1" 2>/dev/null && find . -type f -not -path './.git/*' | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' '); }
commits() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }

# A store made with another key, or one already holding the host's key (e.g. kept by +store-cache).
make_store() {  # make_store DIR KEY
    mkdir -p "$1" && printf '%s\n' "$2" > "$1/.gpg-id"
    mk "$1/gh/user.txt" "cached"; mk "$1/gh/user.txt.sig" "sig-cached"
    git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
}

# ---- 1. nothing asked ----
run_hook "$WORK/h1"
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/h1/.folio" && ! -s "$WORK/gpg.log" ]] \
    && check "true"  "no CB_FOLIO_SEED: no store is made" \
    || check "false" "no CB_FOLIO_SEED: no store is made" "$OUT"

# ---- 2. seed, no store yet ----
run_hook "$WORK/h2" CB_FOLIO_SEED="gh @app2 --secrets"
S="$WORK/h2/.folio"
want=".gitattributes .gpg-id @app2/@prod/server/password.gpg gh/user.txt gh/user.txt.sig "
[[ "$RUN_EXIT" -eq 0 && "$(files "$S")" == "$want" && "$(commits "$S")" == 1 \
   && "$(stat -c %a "$S")" == 700 ]] \
    && check "true"  "seed, no store: the store is the seed (paths and namespaces kept), committed, 700" \
    || check "false" "seed, no store: the store is the seed (paths and namespaces kept), committed, 700" \
         "files: $(files "$S")"$'\n'"commits: $(commits "$S")"$'\n'"$OUT"

grep -q -- "--import $SEED/pubkey.asc" "$WORK/gpg.log" && [[ ! -e "$S/pubkey.asc" ]] \
    && check "true"  "the public key is imported, and not left in the store" \
    || check "false" "the public key is imported, and not left in the store" "$(cat "$WORK/gpg.log")"

run_hook "$WORK/h2" CB_FOLIO_SEED="gh @app2 --secrets"
[[ "$RUN_EXIT" -eq 0 && "$(commits "$S")" == 1 ]] \
    && check "true"  "a restart keeps the store it made (no second seed)" \
    || check "false" "a restart keeps the store it made (no second seed)" "$OUT"

# ---- 3. seed, a store already there (e.g. +store-cache) ----
make_store "$WORK/h3/cache/store" HOSTKEY
run_hook "$WORK/h3" CB_FOLIO_SEED="gh" FOLIO_STORE_DIR="$WORK/h3/cache/store"
[[ "$RUN_EXIT" -eq 0 && "$(files "$WORK/h3/cache/store")" == ".gpg-id gh/user.txt gh/user.txt.sig " \
   && "$(cat "$WORK/h3/cache/store/gh/user.txt")" == cached ]] \
    && check "true"  "seed, store exists: it is used as it is (FOLIO_STORE_DIR honoured)" \
    || check "false" "seed, store exists: it is used as it is (FOLIO_STORE_DIR honoured)" "$(files "$WORK/h3/cache/store")"$'\n'"$OUT"

# ---- 4. fill, same key ----
make_store "$WORK/h4/.folio" HOSTKEY
run_hook "$WORK/h4" CB_FOLIO_SEED="gh @app2 --secrets" CB_FOLIO_SEED_MODE=fill
S="$WORK/h4/.folio"
[[ "$RUN_EXIT" -eq 0 && -f "$S/@app2/@prod/server/password.gpg" && "$(cat "$S/gh/user.txt")" == cached \
   && "$(cat "$S/gh/user.txt.sig")" == sig-cached && "$(commits "$S")" == 2 ]] \
    && check "true"  "fill, same key: missing items added and committed; existing ones (and their .sig) kept" \
    || check "false" "fill, same key: missing items added and committed; existing ones (and their .sig) kept" \
         "files: $(files "$S")"$'\n'"user.txt: $(cat "$S/gh/user.txt")"$'\n'"$OUT"

# ---- 5. fill, another key ----
make_store "$WORK/h5/.folio" BOOTHKEY
run_hook "$WORK/h5" CB_FOLIO_SEED="gh @app2 --secrets" CB_FOLIO_SEED_MODE=fill
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/h5/.folio/@app2" && "$OUT" == *"another key"* ]] \
    && check "true"  "fill, another key: nothing added, and it says why" \
    || check "false" "fill, another key: nothing added, and it says why" "$(files "$WORK/h5/.folio")"$'\n'"$OUT"

# ---- 6. a folder that is not a store ----
mk "$WORK/h6/.folio/notes.txt" "mine"
run_hook "$WORK/h6" CB_FOLIO_SEED="gh"
[[ "$RUN_EXIT" -eq 0 && "$(files "$WORK/h6/.folio")" == "notes.txt " ]] \
    && check "true"  "a non-empty folder that is not a store is left alone" \
    || check "false" "a non-empty folder that is not a store is left alone" "$(files "$WORK/h6/.folio")"$'\n'"$OUT"

# ---- 7. envfolio+agent: gpg is pointed at the host agent's socket ----
SOCK="$WORK/agent.sock"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$SOCK"
run_hook "$WORK/h7" CB_GPG_AGENT_SOCK="$SOCK"
redirect="$WORK/h7/.gnupg/S.gpg-agent"
[[ "$RUN_EXIT" -eq 0 && "$(cat "$redirect" 2>/dev/null)" == $'%Assuan%\nsocket='"$SOCK" \
   && "$(stat -c %a "$WORK/h7/.gnupg")" == 700 && "$(grep -cx no-autostart "$WORK/h7/.gnupg/gpg.conf")" == 1 ]] \
    && check "true"  "agent: gpg's socket is a redirect to the host agent, with no-autostart" \
    || check "false" "agent: gpg's socket is a redirect to the host agent, with no-autostart" \
         "redirect: $(cat "$redirect" 2>&1)"$'\n'"gpg.conf: $(cat "$WORK/h7/.gnupg/gpg.conf" 2>&1)"$'\n'"$OUT"

run_hook "$WORK/h7" CB_GPG_AGENT_SOCK="$SOCK"
[[ "$RUN_EXIT" -eq 0 && "$(grep -cx no-autostart "$WORK/h7/.gnupg/gpg.conf")" == 1 ]] \
    && check "true"  "agent: a restart adds no-autostart once" \
    || check "false" "agent: a restart adds no-autostart once" "$(cat "$WORK/h7/.gnupg/gpg.conf")"

run_hook "$WORK/h8" CB_GPG_AGENT_SOCK="$WORK/no-such.sock"
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/h8/.gnupg/S.gpg-agent" && "$OUT" == *"no host gpg-agent socket"* ]] \
    && check "true"  "agent: no socket mounted -- nothing redirected, and it says so" \
    || check "false" "agent: no socket mounted -- nothing redirected, and it says so" "$OUT"

$ALL_PASSED
