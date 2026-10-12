#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# POST /booth-messages/api/display-lease — picks the one viewer of a desktop
# booth that may fit the desktop to its window; the others scale. Without it,
# two tabs each resized the desktop to their own size and it flickered between
# them. Runs the real booth-message-api-server on the host, one request at a
# time through its --handle mode (as socat does), with the lease file in a temp
# dir:
#   - the first viewer to ask gets it; a second one asking without claiming
#     does not, and the holder keeps it on renewal;
#   - a claim (the viewer was focused) takes it — the last focused wins;
#   - a lease nobody renewed for longer than the TTL goes to the next asker;
#   - a release frees it, but only the holder's own;
#   - a missing or malformed id is rejected and changes nothing.
# That the page acts on the answer — follower scales, holder resizes — is
# checked live against a desktop booth, not here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API="$REPO_ROOT/variants/base/setups/booth-message-api-server"
BASH_BIN="$(command -v bash)"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin"
LEASE="$STUB/lease"

for tool in head sed wc cat mv rm; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

# lease <json> — one request through --handle; sets OUT (status line + body).
lease() {
    local body="$1"
    OUT=$(printf 'POST /booth-messages/api/display-lease HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s' \
            "${#body}" "$body" \
          | env -i HOME="$STUB" PATH="$(stub_path "$STUB/bin")" BOOTH_DISPLAY_LEASE_FILE="$LEASE" "$BASH_BIN" "$API" --handle 2>&1 | tr -d '\r')
}
is_leader()   { grep -q '^HTTP/1.0 200' <<< "$OUT" && grep -q '"leader":true'  <<< "$OUT"; }
is_follower() { grep -q '^HTTP/1.0 200' <<< "$OUT" && grep -q '"leader":false' <<< "$OUT"; }
holder()      { cut -d' ' -f1 "$LEASE" 2>/dev/null || true; }

# ---- first come, and the holder keeps it ----
lease '{"id":"tabA","claim":false}'
A1="$OUT"
lease '{"id":"tabB","claim":false}'
B1="$OUT"
lease '{"id":"tabA","claim":false}'
if grep -q '"leader":true' <<< "$A1" && grep -q '"leader":false' <<< "$B1" && is_leader && [[ "$(holder)" == tabA ]]; then
    check "true"  "The first viewer gets the lease; a second one does not; the holder renews it"
else
    check "false" "The first viewer gets the lease; a second one does not; the holder renews it" "A1=$A1 B1=$B1 A2=$OUT holder=$(holder)"
fi

# ---- a claim takes it: the last focused wins ----
lease '{"id":"tabB","claim":true}'
B2="$OUT"
lease '{"id":"tabA"}'
if grep -q '"leader":true' <<< "$B2" && is_follower && [[ "$(holder)" == tabB ]]; then
    check "true"  "A claim (the viewer was focused) takes the lease from its holder"
else
    check "false" "A claim (the viewer was focused) takes the lease from its holder" "B2=$B2 A=$OUT holder=$(holder)"
fi

# ---- an expired lease goes to the next asker ----
printf 'tabB %s\n' "$(( $(date +%s) - 60 ))" > "$LEASE"
lease '{"id":"tabA"}'
if is_leader && [[ "$(holder)" == tabA ]]; then
    check "true"  "A lease not renewed within the TTL goes to the next viewer to ask"
else
    check "false" "A lease not renewed within the TTL goes to the next viewer to ask" "out=$OUT holder=$(holder)"
fi

# ---- release: only the holder's own ----
lease '{"id":"tabB","release":true}'
B3="$OUT"
HOLDER_AFTER_B="$(holder)"
lease '{"id":"tabA","release":true}'
if grep -q '"leader":false' <<< "$B3" && [[ "$HOLDER_AFTER_B" == tabA ]] && is_follower && [[ ! -e "$LEASE" ]]; then
    check "true"  "A release frees the lease, and a non-holder cannot release it"
else
    check "false" "A release frees the lease, and a non-holder cannot release it" "B3=$B3 holderAfterB=$HOLDER_AFTER_B A=$OUT exists=$([[ -e $LEASE ]] && echo yes || echo no)"
fi

# ---- a released lease is free again ----
lease '{"id":"tabB"}'
if is_leader && [[ "$(holder)" == tabB ]]; then
    check "true"  "Once released, the next viewer to ask gets it"
else
    check "false" "Once released, the next viewer to ask gets it" "out=$OUT holder=$(holder)"
fi

# ---- bad ids are rejected and change nothing ----
REJECTED=0
for body in '{}' '{"claim":true}' '{"id":"","claim":true}' '{"id":"a b","claim":true}' '{"id":"../x","claim":true}' \
            "{\"id\":\"$(printf 'x%.0s' {1..65})\",\"claim\":true}"; do
    lease "$body"
    grep -q '^HTTP/1.0 400' <<< "$OUT" && REJECTED=$((REJECTED + 1))
done
if [[ "$REJECTED" -eq 6 && "$(holder)" == tabB ]]; then
    check "true"  "Missing, empty, odd-character and over-long ids: 400, lease unchanged"
else
    check "false" "Missing, empty, odd-character and over-long ids: 400, lease unchanged" "rejected=$REJECTED/6 holder=$(holder)"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
