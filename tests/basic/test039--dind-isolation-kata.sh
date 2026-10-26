#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --dind-isolation kata (experimental) really puts the DinD sidecar in a VM.
#
# Starts a --dind-isolation booth with no terminal (so no consent prompt may be
# needed), then checks the claims the docs make (docs/BOOTH_SECURITY.md#dind-isolation):
# the sidecar runs on the Kata runtime and is not --privileged, its daemon runs
# another kernel, a nested --privileged container sees none of the host's disks
# (the escape plain --dind allows), and the booth's localhost still reaches a port
# the sidecar publishes.
#
# The base image has no docker CLI, so the sidecar's daemon is driven from the
# host with docker:cli on the DinD network, and forwarding is checked through a
# run-args publish (the fixed half of booth--dind-forward).
#
# Skips — exit 0 — where Kata cannot run: macOS, Windows, Docker Desktop, no
# /dev/kvm, or no Kata installed (kata_supported in tests/common--source.sh).
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh
sidecars_supported --dind || exit 0
kata_supported || exit 0
no_tty_supported || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTH="$(find_local_booth_build "$SCRIPT_DIR")"

TEST_DIR=$(mktemp -d)
NAME="cb-test039-kata-$$"
PORT="$(pick_free_port)"
FWD_PORT="$(pick_free_port_other_than "$PORT")"
SIDECAR="$NAME-$PORT-dind"
NET="$NAME-$PORT-net"
trap 'docker rm -f "$NAME" "$SIDECAR" >/dev/null 2>&1 || true
      docker network rm "$NET" >/dev/null 2>&1 || true
      rm -rf "$TEST_DIR" 2>/dev/null || true' EXIT
mkdir -p "$TEST_DIR/.booth"

FAILED=0
check() { # check <ok> <n> <description> <actual>
    if [[ "$1" == "true" ]]; then
        print_test_result "true" "$0" "$2" "$3"
    else
        print_test_result "false" "$0" "$2" "$3"
        echo "  Actual: $4"
        FAILED=$((FAILED + 1))
    fi
}

# on_sidecar ARGS... : a docker command against the sidecar's own daemon.
on_sidecar() {
    docker run --rm --network "$NET" docker:cli docker -H "tcp://$SIDECAR:2375" "$@"
}

# 1. Starts with no terminal and no --dind-allowed: a Kata sidecar asks nothing.
STATUS=0
OUTPUT=$(cd "$TEST_DIR" && no_tty_run "$BOOTH" --name "$NAME" --variant base --port "$PORT" \
    --dind-isolation --daemon --keep-alive -p "$FWD_PORT:8080" </dev/null 2>&1) || STATUS=$?
check "$([[ $STATUS -eq 0 ]] && echo true || echo false)" 1 \
    "A --dind-isolation booth starts without a consent prompt" "exit $STATUS: $(tail -5 <<<"$OUTPUT")"
if [[ $STATUS -ne 0 ]]; then
    exit 1
fi

for _ in {1..60}; do
    on_sidecar version >/dev/null 2>&1 && break
    sleep 2
done

# 2. The sidecar is on the Kata runtime, and not privileged.
RUNTIME=$(docker inspect -f '{{.HostConfig.Runtime}} {{.HostConfig.Privileged}}' "$SIDECAR" 2>&1 || true)
check "$([[ "$RUNTIME" == "io.containerd.kata.v2 false" ]] && echo true || echo false)" 2 \
    "The DinD sidecar runs on io.containerd.kata.v2, not --privileged" "$RUNTIME"

# 3. Its daemon runs a kernel of its own (the VM's), not the host's.
HOST_KERNEL=$(uname -r)
DAEMON_KERNEL=$(on_sidecar info --format '{{.KernelVersion}}' 2>/dev/null || true)
check "$([[ -n "$DAEMON_KERNEL" && "$DAEMON_KERNEL" != "$HOST_KERNEL" ]] && echo true || echo false)" 3 \
    "The sidecar's daemon runs its VM's kernel, not the host's ($HOST_KERNEL)" "daemon kernel: '$DAEMON_KERNEL'"

# 4. The escape plain --dind allows: a nested --privileged container sees the host's disks.
HOST_DISKS=$(ls /dev | grep -E '^(nvme|sd[a-z]|vd[a-z]|xvd[a-z])' | tr '\n' ' ' || true)
NESTED_DISKS=$(on_sidecar run --rm --privileged alpine sh -c \
    'ls /dev | grep -E "^(nvme|sd[a-z]|vd[a-z]|xvd[a-z])" | tr "\n" " "; echo "[done]"' 2>&1 | tail -1 || true)
check "$([[ "$NESTED_DISKS" == "[done]" ]] && echo true || echo false)" 4 \
    "A nested --privileged container sees none of the host's disks (host has: ${HOST_DISKS:-none})" "$NESTED_DISKS"

# 5. The booth's localhost reaches a port the sidecar publishes (booth--dind-forward).
on_sidecar run -d --name web -p 8080:8080 alpine sh -c \
    'while true; do echo -e "HTTP/1.0 200 OK\r\n\r\nkata-forwarded" | nc -l -p 8080; done' >/dev/null 2>&1 || true
BODY=""
for _ in {1..30}; do
    BODY=$(docker exec "$NAME" curl -s -m 3 http://localhost:8080/ 2>/dev/null || true)
    [[ "$BODY" == *kata-forwarded* ]] && break
    sleep 1
done
check "$([[ "$BODY" == *kata-forwarded* ]] && echo true || echo false)" 5 \
    "The booth's localhost:8080 reaches the container the sidecar publishes" "body: '$BODY'"

# 6. The booth publishes its own front door now (the sidecar no longer owns its network).
FRONT=$(docker port "$NAME" 10000/tcp 2>&1 || true)
check "$([[ "$FRONT" == *":$PORT" ]] && echo true || echo false)" 6 \
    "The booth publishes its own port $PORT" "$FRONT"

exit $FAILED
