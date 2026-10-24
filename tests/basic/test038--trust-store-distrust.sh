#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: no trust store in a codeserver booth still trusts the eMudhra CA chains
# compromised in Oct 2026 — the system bundle, pip's vendored certifi, certifi
# itself, and code-server's bundled Node (which must verify against the system
# store). Each carries its own copy of the roots, so each can regress on its own:
# a cached image layer kept pip 26.2.1, and code-server 4.141.0's Node shipped
# with the bad roots. Offline: fingerprints, not a live handshake (see
# tests/manual/emudhra-live-check.sh for that).

set -euo pipefail

source ../common--source.sh

NAME="trust-store-test-$RANDOM"
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"
cp fixtures/trust-store/distrusted-in-bundle.py "$WORK/"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

run_coding_booth --variant codeserver --code "$WORK" --name "$NAME" --port "$PORT" --daemon --keep-alive \
  > "$0.log" 2>&1 || true

in_booth() { docker exec -u root "$NAME" bash -c "$1" 2>&1 || true; }
check() {
  local number="$1" result="$2" description="$3"
  print_test_result "$result" "$0" "$number" "$description"
  [[ "$result" == true ]]
}

CHECK="python3 /home/coder/code/distrusted-in-bundle.py"

# 1. The system bundle — what curl, wget, git, apt and Go programs trust.
found=$(in_booth "$CHECK /etc/ssl/certs/ca-certificates.crt")
check 1 "$([[ -z "$found" ]] && echo true || echo false)" \
  "System CA bundle trusts none of the compromised eMudhra chains${found:+ — found: $found}" || exit 1

# 2. pip verifies with its own vendored certifi, never the system store.
found=$(in_booth "$CHECK \"\$(python3 -c 'import pip._vendor.certifi as c; print(c.where())')\"")
check 2 "$([[ -z "$found" ]] && echo true || echo false)" \
  "pip's vendored certifi trusts none of them${found:+ — found: $found}" || exit 1

# 3. certifi — what requests, httpx and most Python HTTP clients use.
found=$(in_booth "$CHECK \"\$(python3 -c 'import certifi; print(certifi.where())')\"")
check 3 "$([[ -z "$found" ]] && echo true || echo false)" \
  "certifi trusts none of them${found:+ — found: $found}" || exit 1

# 4. code-server's own Node carries a root list frozen at its release; it must be
#    told to use the system store instead. Wait for the process, then read the
#    option off its environment, which its extension host and terminals inherit.
pid=""
for _ in {1..60}; do
  pid=$(in_booth "pgrep -f '^/usr/lib/code-server/lib/node /usr/lib/code-server' | head -1")
  [[ "$pid" =~ ^[0-9]+$ ]] && break
  pid=""
  sleep 1
done
opts=""
if [[ -n "$pid" ]]; then
  # Read as the process's own user: exec'd root lacks CAP_SYS_PTRACE, which
  # another user's /proc/<pid>/environ requires.
  owner=$(in_booth "stat -c %u /proc/$pid")
  opts=$(docker exec -u "$owner" "$NAME" bash -c "tr '\\0' '\\n' < /proc/$pid/environ | sed -n 's/^NODE_OPTIONS=//p'" 2>&1 || true)
fi
check 4 "$([[ " $opts " == *" --use-openssl-ca "* ]] && echo true || echo false)" \
  "code-server's Node verifies against the system CA store (pid '${pid}', NODE_OPTIONS '${opts}')" || exit 1
