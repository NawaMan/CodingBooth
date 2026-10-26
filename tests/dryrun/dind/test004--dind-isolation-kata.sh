#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: --dind-isolation kata (experimental) runs the DinD sidecar in a Kata VM
#
# The sidecar gets the Kata runtime and no --privileged (Kata's --privileged hands
# the host's devices to the VM). A VM has its own network, so the booth joins the
# DinD network instead of the sidecar's namespace, reaches the daemon by name,
# publishes its own front door, and is told which run-args ports to forward on
# localhost. --dryrun skips the Kata preflight, so this runs on any host.

set -euo pipefail

source ../../common--source.sh
sidecars_supported --dind || exit 0

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

ACTUAL=$(run_coding_booth --config test--config.toml --dryrun --dind-isolation 2>&1 | strip_ansi)
SIDECAR=$(echo "$ACTUAL" | grep -- "--runtime io.containerd.kata.v2" || true)
BOOTH_CMD=$(echo "$ACTUAL" | sed -n '/Running booth in foreground/,/^docker.*stop/p')

check() { # check <n> <description> <command...>
    local n="$1" desc="$2"
    shift 2
    if "$@"; then
        print_test_result "true" "$0" "$n" "$desc"
    else
        print_test_result "false" "$0" "$n" "$desc"
        echo "--- sidecar:"; echo "$SIDECAR"
        echo "--- booth:"; echo "$BOOTH_CMD"
        exit 1
    fi
}
has()     { grep -q -- "$2" <<<"$1"; }
has_not() { ! grep -q -- "$2" <<<"$1"; }

check 1 "Experimental warning is printed"            has "$ACTUAL" "Warning: --dind-isolation kata is experimental"
check 2 "Sidecar runs on the Kata runtime"           test -n "$SIDECAR"
check 3 "Sidecar is not --privileged"                has_not "$SIDECAR" "--privileged"
check 4 "Sidecar publishes the run-args ports"       has "$SIDECAR" "-p 8080:8080 -p 3000:3000"
check 5 "Sidecar does not publish the front door"    has_not "$SIDECAR" ":10000"
check 6 "Booth joins the DinD network, not its netns" has "$BOOTH_CMD" "--network dind-10000-net"
check 7 "Booth does not share the sidecar's netns"   has_not "$BOOTH_CMD" "--network container:"
check 8 "Booth reaches the daemon by name"           has "$BOOTH_CMD" "DOCKER_HOST=tcp://dind-10000-dind:2375"
check 9 "Booth forwards the run-args ports"          has "$BOOTH_CMD" "BOOTH_DIND_FORWARD=8080 3000"
check 10 "Booth publishes its own front door"        has "$BOOTH_CMD" "-p 127.0.0.1:10000:10000"
check 11 "No consent prompt (sidecar is its own VM)" has_not "$ACTUAL" "reach the host"

# The same through the environment variable and the config key.
FROM_ENV=$(CB_DIND_ISOLATION=kata run_coding_booth --config test--config.toml --dryrun 2>&1 | strip_ansi)
check 12 "CB_DIND_ISOLATION=kata selects it"         has "$FROM_ENV" "--runtime io.containerd.kata.v2"

# mktemp -d, not --suffix: BSD mktemp (macOS) has no --suffix.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_CONFIG="$TMP_DIR/config.toml"
printf 'variant = "base"\ndind-isolation = "kata"\ndind-vm-memory = "4g"\ndind-vm-cpus = "2"\n' > "$TMP_CONFIG"
FROM_TOML=$(run_coding_booth --config "$TMP_CONFIG" --dryrun 2>&1 | strip_ansi)
check 13 "dind-isolation in config.toml selects it (and implies dind)" has "$FROM_TOML" "--runtime io.containerd.kata.v2"
check 14 "dind-vm-memory sizes the VM"               has "$FROM_TOML" "io.katacontainers.config.hypervisor.default_memory=4096"
check 15 "dind-vm-cpus sizes the VM"                 has "$FROM_TOML" "io.katacontainers.config.hypervisor.default_vcpus=2"

# Refused where Kata cannot run.
if PODMAN=$(run_coding_booth --config test--config.toml --dryrun --dind-isolation --engine podman 2>&1); then
    check 16 "Refused on engine podman" false
else
    check 16 "Refused on engine podman" has "$PODMAN" "needs engine docker"
fi
