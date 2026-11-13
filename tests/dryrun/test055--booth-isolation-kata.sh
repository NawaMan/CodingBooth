#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: --booth-isolation kata (experimental) runs the booth itself in a Kata VM —
# and falls back, loudly, where this machine cannot run Kata.
#
# Where Kata runs (kata_supported): one flag, CB_BOOTH_ISOLATION or the config key
# gives the booth's own `docker run` the Kata runtime, a VM sized by annotation
# (4g / 2 CPUs unless --vm-memory / --vm-cpus say otherwise) and a resolv.conf of
# the host's real resolvers. Run-args a VM cannot honour are refused, and --dind
# puts the sidecar in Kata too. Elsewhere those checks are skipped.
#
# Everywhere: with Kata out of reach — here by hiding its shim from PATH — the run
# says so in a banner and becomes an ordinary container.

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

check() { # check <n> <description> <command...>
    local n="$1" desc="$2"
    shift 2
    if "$@"; then
        print_test_result "true" "$0" "$n" "$desc"
    else
        print_test_result "false" "$0" "$n" "$desc"
        echo "--- output:"; echo "${LAST_OUTPUT:-}" | tail -40
        exit 1
    fi
}
has()     { grep -q -- "$2" <<<"$1"; }
has_not() { ! grep -q -- "$2" <<<"$1"; }

# mktemp -d, not --suffix: BSD mktemp (macOS) has no --suffix.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
WS="$TMP_DIR/kata-ws"
mkdir -p "$WS/.booth"
printf 'variant = "base"\n' > "$WS/.booth/config.toml"

booth_dryrun() { run_coding_booth --code "$WS" --dryrun "$@" -- true 2>&1 | strip_ansi || true; }

if kata_supported; then
    ACTUAL=$(booth_dryrun --booth-isolation)
    LAST_OUTPUT="$ACTUAL"
    check 1 "Experimental warning is printed"          has "$ACTUAL" "Warning: --booth-isolation kata is experimental"
    check 2 "The booth runs on the Kata runtime"       has "$ACTUAL" "--runtime io.containerd.kata.v2"
    check 3 "The VM gets 4g by default"                has "$ACTUAL" "default_memory=4096"
    check 4 "The VM gets 2 CPUs by default"            has "$ACTUAL" "default_vcpus=2"
    check 5 "The VM gets the host's resolvers"         has "$ACTUAL" ":/etc/resolv.conf:ro"
    check 6 "The booth is labelled"                    has "$ACTUAL" "cb.booth-isolation=kata"
    check 7 "No --privileged"                          has_not "$ACTUAL" "--privileged"
    check 8 "No fallback banner where Kata runs"       has_not "$ACTUAL" "NOT AVAILABLE ON THIS MACHINE"

    SIZED=$(booth_dryrun --booth-isolation=kata --vm-memory 8g --vm-cpus 4)
    LAST_OUTPUT="$SIZED"
    check 9 "--vm-memory sizes the VM"                 has "$SIZED" "default_memory=8192"
    check 10 "--vm-cpus sizes the VM"                  has "$SIZED" "default_vcpus=4"
    check 11 "No apple-only note about --vm-*"         has_not "$SIZED" "only apply to engine apple"

    FROM_ENV=$(CB_BOOTH_ISOLATION=kata booth_dryrun)
    LAST_OUTPUT="$FROM_ENV"
    check 12 "CB_BOOTH_ISOLATION=kata selects it"      has "$FROM_ENV" "--runtime io.containerd.kata.v2"

    printf 'variant = "base"\nbooth-isolation = "kata"\n' > "$WS/.booth/config.toml"
    FROM_TOML=$(booth_dryrun)
    LAST_OUTPUT="$FROM_TOML"
    check 13 "booth-isolation in config.toml selects it" has "$FROM_TOML" "--runtime io.containerd.kata.v2"
    NONE=$(booth_dryrun --booth-isolation none)
    LAST_OUTPUT="$NONE"
    check 14 "--booth-isolation none overrides config" has_not "$NONE" "io.containerd.kata.v2"
    printf 'variant = "base"\n' > "$WS/.booth/config.toml"

    REFUSED=$(booth_dryrun --booth-isolation --privileged --gpus all)
    LAST_OUTPUT="$REFUSED"
    check 15 "--privileged and --gpus are refused"     has "$REFUSED" "cannot run a booth with --privileged, --gpus"
    check 16 "Refused before anything runs"            has_not "$REFUSED" "docker \\\\"

    EGRESS=$(booth_dryrun --booth-isolation --egress)
    LAST_OUTPUT="$EGRESS"
    check 17 "--egress is refused"                     has "$EGRESS" "cannot be combined with --egress"

    DIND=$(booth_dryrun --booth-isolation --dind)
    LAST_OUTPUT="$DIND"
    check 18 "With --dind the sidecar is in Kata too"  has "$DIND" "cb.dind-isolation=kata"
    check 19 "No privileged docker:dind sidecar"       has_not "$DIND" "--privileged"
    check 20 "The booth finds the sidecar by --add-host" has "$DIND" "--add-host '\\?kata-ws-10000-dind:"
else
    echo "SKIP: tests 1-20 (the Kata shape) need a host that runs Kata; the fallback below still runs."
fi

# --- Everywhere: no Kata on this machine → loud fallback to an ordinary container
mkdir -p "$TMP_DIR/bin"
ln -s "$(type -P docker)" "$TMP_DIR/bin/docker"
FALLBACK=$(PATH="$TMP_DIR/bin:/usr/bin:/bin" booth_dryrun --booth-isolation)
LAST_OUTPUT="$FALLBACK"
check 21 "No Kata here: the banner says so"        has "$FALLBACK" "BOOTH ISOLATION (KATA) WAS ASKED FOR, BUT IS NOT AVAILABLE"
check 22 "No Kata here: it says what runs instead" has "$FALLBACK" "ORDINARY CONTAINER"
check 23 "No Kata here: no Kata runtime"           has_not "$FALLBACK" "io.containerd.kata.v2"
check 24 "No Kata here: the booth still runs"      has "$FALLBACK" "run \\\\"
