#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: --dind-isolation kata (experimental) runs the DinD sidecar in a Kata VM —
# and falls back, loudly, where this machine cannot run Kata.
#
# Where Kata runs (kata_supported): the sidecar gets the Kata runtime and no
# --privileged (Kata's --privileged hands the host's devices to the VM). A VM has
# its own network, so the booth joins the DinD network instead of the sidecar's
# namespace, reaches the daemon by name, publishes its own front door, and is told
# which run-args ports to forward on localhost. Elsewhere (macOS, Windows, Docker
# Desktop, no KVM or Kata) those checks are skipped.
#
# Everywhere: with Kata out of reach — here by hiding its shim from PATH, which is
# what a Linux host without Kata looks like — the run says so in a banner and
# becomes the plain privileged sidecar, which the usual --dind consent then covers
# (tests/dryrun/test043, pkg/booth/dind_kata_test.go). --dryrun runs the same
# check a real run does, so it prints what this machine would run.

set -euo pipefail

source ../../common--source.sh
sidecars_supported --dind || exit 0

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

# --- Where Kata runs: the Kata shape ------------------------------------------
if kata_supported; then
    ACTUAL=$(run_coding_booth --config test--config.toml --dryrun --dind-isolation 2>&1 | strip_ansi)
    LAST_OUTPUT="$ACTUAL"
    SIDECAR=$(echo "$ACTUAL" | grep -- "--runtime io.containerd.kata.v2" || true)
    BOOTH_CMD=$(echo "$ACTUAL" | sed -n '/Running booth in foreground/,/^docker.*stop/p')

    check 1 "Experimental warning is printed"             has "$ACTUAL" "Warning: --dind-isolation kata is experimental"
    check 2 "Sidecar runs on the Kata runtime"            test -n "$SIDECAR"
    check 3 "Sidecar is not --privileged"                 has_not "$SIDECAR" "--privileged"
    check 4 "Sidecar publishes the run-args ports"        has "$SIDECAR" "-p 8080:8080 -p 3000:3000"
    check 5 "Sidecar does not publish the front door"     has_not "$SIDECAR" ":10000"
    check 6 "Booth joins the DinD network, not its netns" has "$BOOTH_CMD" "--network dind-10000-net"
    check 7 "Booth does not share the sidecar's netns"    has_not "$BOOTH_CMD" "--network container:"
    check 8 "Booth reaches the daemon by name"            has "$BOOTH_CMD" "DOCKER_HOST=tcp://dind-10000-dind:2375"
    check 9 "Booth forwards the run-args ports"           has "$BOOTH_CMD" "BOOTH_DIND_FORWARD=8080 3000"
    check 10 "Booth publishes its own front door"         has "$BOOTH_CMD" "-p 127.0.0.1:10000:10000"
    check 11 "No fallback banner where Kata runs"         has_not "$ACTUAL" "NOT AVAILABLE ON THIS MACHINE"

    # The same through the environment variable and the config key.
    FROM_ENV=$(CB_DIND_ISOLATION=kata run_coding_booth --config test--config.toml --dryrun 2>&1 | strip_ansi)
    LAST_OUTPUT="$FROM_ENV"
    check 12 "CB_DIND_ISOLATION=kata selects it"          has "$FROM_ENV" "--runtime io.containerd.kata.v2"

    printf 'variant = "base"\ndind-isolation = "kata"\ndind-vm-memory = "4g"\ndind-vm-cpus = "2"\n' > "$TMP_DIR/config.toml"
    FROM_TOML=$(run_coding_booth --config "$TMP_DIR/config.toml" --dryrun 2>&1 | strip_ansi)
    LAST_OUTPUT="$FROM_TOML"
    check 13 "dind-isolation in config.toml selects it (and implies dind)" has "$FROM_TOML" "--runtime io.containerd.kata.v2"
    check 14 "dind-vm-memory sizes the VM"                has "$FROM_TOML" "io.katacontainers.config.hypervisor.default_memory=4096"
    check 15 "dind-vm-cpus sizes the VM"                  has "$FROM_TOML" "io.katacontainers.config.hypervisor.default_vcpus=2"
else
    echo "SKIP: tests 1-15 (the Kata shape) need a host that runs Kata; the fallback below still runs."
fi

# --- Everywhere: no Kata on this machine → loud fallback to the plain sidecar --
# A PATH holding only docker (and the system dirs) hides containerd-shim-kata-v2,
# which normally lives in /usr/local/bin. On a host without Kata nothing changes.
mkdir -p "$TMP_DIR/bin"
ln -s "$(command -v docker)" "$TMP_DIR/bin/docker"
FALLBACK=$(PATH="$TMP_DIR/bin:/usr/bin:/bin" run_coding_booth --config test--config.toml --dryrun --dind-isolation 2>&1 | strip_ansi)
LAST_OUTPUT="$FALLBACK"
check 16 "No Kata here: the banner says so"           has "$FALLBACK" "NOT AVAILABLE ON THIS MACHINE"
check 17 "No Kata here: it names the privileged sidecar" has "$FALLBACK" "PLAIN, PRIVILEGED DinD sidecar"
check 18 "No Kata here: the plain docker:dind sidecar runs" has "$FALLBACK" "docker:dind"
check 19 "No Kata here: no Kata runtime"              has_not "$FALLBACK" "io.containerd.kata.v2"
check 20 "No Kata here: the booth shares the sidecar's netns, as plain --dind" has "$FALLBACK" "--network container:dind-10000-dind"

# An engine Kata cannot run on falls back the same way.
PODMAN=$(run_coding_booth --config test--config.toml --dryrun --dind-isolation --engine podman 2>&1 | strip_ansi || true)
LAST_OUTPUT="$PODMAN"
check 21 "Engine podman: falls back with the banner"   has "$PODMAN" "needs engine docker"
