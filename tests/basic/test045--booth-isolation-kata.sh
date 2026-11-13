#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --booth-isolation kata (experimental) really puts the booth in a VM.
#
# Starts a --booth-isolation booth, then checks the claims the docs make
# (docs/BOOTH_SECURITY.md#booth-isolation): the booth runs on the Kata runtime,
# under another kernel, in a VM of the default size; coder is still the host's
# uid and its files land on the host as that uid; names resolve; the front door
# answers; and the host's disks are not in the booth's /dev. Then a second booth
# with --dind: its sidecar is in Kata too, and the booth reaches it by name. And
# a third with --egress: alone on an internal network behind the egress gateway.
#
# Skips — exit 0 — where Kata cannot run: macOS, Windows, Docker Desktop, no
# /dev/kvm, or no Kata installed (kata_supported in tests/common--source.sh).
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh
kata_supported || exit 0
no_tty_supported || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTH="$(find_local_booth_build "$SCRIPT_DIR")"

TEST_DIR=$(mktemp -d)
NAME="cb-test045-kata-$$"
PORT="$(pick_free_port)"
DIND_NAME="$NAME-dind"
DIND_PORT="$(pick_free_port_other_than "$PORT")"
SIDECAR="$DIND_NAME-$DIND_PORT-dind"
NET="$DIND_NAME-$DIND_PORT-net"
EGRESS_NAME="$NAME-egress"
EGRESS_PORT="$(pick_free_port_other_than "$PORT" "$DIND_PORT")"
EGRESS_PREFIX="$EGRESS_NAME-$EGRESS_PORT-egress"
trap 'docker rm -f "$NAME" "$DIND_NAME" "$SIDECAR" "$EGRESS_NAME" "$EGRESS_PREFIX-proxy" "$EGRESS_PREFIX-netns" >/dev/null 2>&1 || true
      for _ in 1 2 3 4 5; do  # a Kata VM can take a moment to let go of its network
          docker network rm "$NET" "$EGRESS_PREFIX-int" "$EGRESS_PREFIX-net" >/dev/null 2>&1 || true
          docker network ls --format "{{.Name}}" | grep -q "^$NAME-" || break
          sleep 1
      done
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
ok() { "$@" && echo true || echo false; }
in_booth() { docker exec -u coder "$1" bash -c "$2" 2>&1 || true; }

# 1. Starts with one flag.
STATUS=0
OUTPUT=$(cd "$TEST_DIR" && no_tty_run "$BOOTH" --name "$NAME" --variant base --port "$PORT" \
    --booth-isolation --daemon --keep-alive </dev/null 2>&1) || STATUS=$?
check "$(ok test $STATUS -eq 0)" 1 "A --booth-isolation booth starts" "exit $STATUS: $(tail -5 <<<"$OUTPUT")"
if [[ $STATUS -ne 0 ]]; then
    exit 1
fi

# 2. It is on the Kata runtime, and not privileged.
RUNTIME=$(docker inspect -f '{{.HostConfig.Runtime}} {{.HostConfig.Privileged}}' "$NAME" 2>&1 || true)
check "$(ok test "$RUNTIME" == "io.containerd.kata.v2 false")" 2 \
    "The booth runs on io.containerd.kata.v2, not --privileged" "$RUNTIME"

# 3. Under a kernel of its own (the VM's), not the host's.
HOST_KERNEL=$(uname -r)
BOOTH_KERNEL=$(in_booth "$NAME" 'uname -r')
check "$(ok test -n "$BOOTH_KERNEL" -a "$BOOTH_KERNEL" != "$HOST_KERNEL")" 3 \
    "The booth runs its VM's kernel, not the host's ($HOST_KERNEL)" "booth kernel: '$BOOTH_KERNEL'"

# 4. In a VM of the default size (2 CPUs), not Kata's own 1.
CPUS=$(in_booth "$NAME" 'nproc')
check "$(ok test "$CPUS" == "2")" 4 "The VM has the default 2 CPUs" "nproc: '$CPUS'"

# 5. coder is still the host's uid, and a file it writes lands on the host as that uid.
in_booth "$NAME" 'touch ~/code/written-in-vm' >/dev/null
BOOTH_UID=$(in_booth "$NAME" 'id -u')
FILE_UID=$(stat -c '%u' "$TEST_DIR/written-in-vm" 2>&1 || true)
check "$(ok test "$BOOTH_UID" == "$(id -u)" -a "$FILE_UID" == "$(id -u)")" 5 \
    "coder is uid $(id -u), and its files land on the host as that uid" "coder uid '$BOOTH_UID', file uid '$FILE_UID'"

# 6. Names resolve inside the VM.
DNS=$(in_booth "$NAME" 'getent hosts github.com >/dev/null && echo ok')
check "$(ok test "$DNS" == "ok")" 6 "github.com resolves inside the VM" "$DNS"

# 7. The front door answers on the host.
CODE="000"
for _ in {1..60}; do
    CODE=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null || true)
    [[ "$CODE" != "000" ]] && break
    sleep 2
done
check "$(ok test "$CODE" != "000")" 7 "The booth's port $PORT answers on the host" "http code: $CODE"

# 8. The host's disks are not in the booth's /dev (a container shares them; a VM does not).
BOOTH_DISKS=$(in_booth "$NAME" 'ls /dev | grep -E "^(nvme|sd[a-z])" | tr "\n" " "; echo "[done]"' | tail -1)
check "$(ok test "$BOOTH_DISKS" == "[done]")" 8 "None of the host's nvme/sd disks are in the booth" "$BOOTH_DISKS"

# 11. Docker's usual open-file limit, not Kata's 2^30 (Erlang's VM sizes its port table by it).
NOFILE=$(in_booth "$NAME" 'ulimit -n')
check "$(ok test "$NOFILE" == "1024")" 11 "The booth's open-file limit is Docker's usual 1024, not Kata's 2^30" "ulimit -n: '$NOFILE'"

# 9-10. With --dind: the sidecar goes into Kata too, and the booth reaches its daemon by name.
STATUS=0
OUTPUT=$(cd "$TEST_DIR" && no_tty_run "$BOOTH" --name "$DIND_NAME" --variant base --port "$DIND_PORT" \
    --booth-isolation --dind --daemon --keep-alive </dev/null 2>&1) || STATUS=$?
SIDECAR_RUNTIME=$(docker inspect -f '{{.HostConfig.Runtime}} {{.HostConfig.Privileged}}' "$SIDECAR" 2>&1 || true)
check "$(ok test $STATUS -eq 0 -a "$SIDECAR_RUNTIME" == "io.containerd.kata.v2 false")" 9 \
    "With --dind, no consent is needed and the sidecar runs in Kata" "exit $STATUS, sidecar: '$SIDECAR_RUNTIME' $(tail -3 <<<"$OUTPUT")"
PING=""
for _ in {1..30}; do
    PING=$(in_booth "$DIND_NAME" "curl -s -m 3 http://$SIDECAR:2375/_ping")
    [[ "$PING" == "OK" ]] && break
    sleep 2
done
check "$(ok test "$PING" == "OK")" 10 "The booth reaches the sidecar's daemon by name" "ping: '$PING'"

# 12-15. With --egress: the booth is still a Kata VM, alone on an internal
# network; its front door answers through the egress gateway, the proxy lets
# allowed traffic out, and nothing else leaves — even for root.
STATUS=0
OUTPUT=$(cd "$TEST_DIR" && CB_EGRESS_ALLOWLIST=pypi.org no_tty_run "$BOOTH" --name "$EGRESS_NAME" --variant base --port "$EGRESS_PORT" \
    --booth-isolation --egress --daemon --keep-alive </dev/null 2>&1) || STATUS=$?
EGRESS_RUN=$(docker inspect -f '{{.HostConfig.Runtime}} {{.HostConfig.NetworkMode}}' "$EGRESS_NAME" 2>&1 || true)
check "$(ok test $STATUS -eq 0 -a "$EGRESS_RUN" == "io.containerd.kata.v2 $EGRESS_PREFIX-int")" 12 \
    "With --egress the booth runs in Kata, on the internal network" "exit $STATUS, '$EGRESS_RUN' $(tail -3 <<<"$OUTPUT")"
CODE="000"
for _ in {1..60}; do
    CODE=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$EGRESS_PORT/" 2>/dev/null || true)
    [[ "$CODE" != "000" ]] && break
    sleep 2
done
check "$(ok test "$CODE" != "000")" 13 "Its port $EGRESS_PORT answers on the host, through the gateway" "http code: $CODE"
PROXIED="000"
for _ in {1..15}; do
    PROXIED=$(in_booth "$EGRESS_NAME" 'curl -s -o /dev/null -m 10 -w "%{http_code}" -x http://127.0.0.1:15001 https://pypi.org')
    [[ "$PROXIED" =~ ^[23] ]] && break
    sleep 2
done
check "$(ok test -n "$PROXIED" -a "${PROXIED:0:1}" != "0")" 14 "An allowed site is reached through 127.0.0.1:15001" "http code: '$PROXIED'"
DIRECT=$(docker exec "$EGRESS_NAME" bash -c 'curl -s -o /dev/null -m 8 -w "%{http_code}" --noproxy "*" https://pypi.org; echo " exit $?"' 2>&1 || true)
check "$(ok test "${DIRECT%% *}" == "000")" 15 "A direct connection fails, even as root" "$DIRECT"

exit $FAILED
