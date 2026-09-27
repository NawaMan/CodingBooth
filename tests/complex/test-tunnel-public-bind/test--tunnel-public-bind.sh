#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: booth--expose tunnels bind to every interface for a public booth
#
# "Where the tunnel listens follows the booth" (docs/BOOTH_EXPOSE.md): a
# booth started without --public keeps its tunnels on localhost; one started
# with --public binds them to every interface, same as its own published
# port. Verifies both sides of that, end to end (an actual TCP connect, not
# just parsing the control file):
# 1) Default booth: tunnel control file appears on host
# 2) Default booth: tunnel is reachable on loopback
# 3) Default booth: tunnel is NOT reachable off loopback
# 4) --public booth: tunnel control file appears on host
# 5) --public booth: tunnel is still reachable on loopback
# 6) --public booth: tunnel IS reachable off loopback
# 7) --public booth: booth--expose refuses without --ok-public
# 7b) --public booth: booth--expose --ok-public proceeds and still warns
# 8) Default booth: booth--expose stays quiet about that same tunnel
#
# booth--expose needs the host-side CLI process alive to watch
# .booth/.tmp/tcp-tunnels/ (docs/BOOTH_EXPOSE.md: "Foreground mode
# required") -- plain --daemon detaches before that watcher ever starts, so
# this runs the booth in the foreground with a long-lived command,
# backgrounded here so the test can drive the still-running container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

# The booth--expose warning (tests 7-8) lives in a base-image setup script
# (variants/base/setups/booth--expose), not shipped to Docker Hub yet, so
# this needs the locally-rebuilt base image or those two cases would silently
# test the older, unmodified script. Skips gracefully when that image is not
# present (see use_local_base_image's own doc comment in common--source.sh).
use_local_base_image || exit 0

FAILED=0
SUFFIX=$$
NAME_PRIVATE="test-tunpub-priv-$SUFFIX"
NAME_PUBLIC="test-tunpub-pub-$SUFFIX"
PID_PRIVATE=""
PID_PUBLIC=""

cleanup() {
  [ -n "$PID_PRIVATE" ] && kill "$PID_PRIVATE" >/dev/null 2>&1 || true
  [ -n "$PID_PUBLIC" ] && kill "$PID_PUBLIC" >/dev/null 2>&1 || true
  run_coding_booth remove --force --name "$NAME_PRIVATE" >/dev/null 2>&1 || true
  run_coding_booth remove --force --name "$NAME_PUBLIC" >/dev/null 2>&1 || true
  rm -f .booth/.booth.password
  reset_booth_tmp
}
trap cleanup EXIT

reset_booth_tmp

BOOTH_BIN="$(find_local_booth_build "$SCRIPT_DIR")" || {
  echo "ERROR: could not find local codingbooth build" >&2
  exit 1
}

# nonloopback_ipv4 prints a host IPv4 address other than 127.0.0.1, or nothing
# on a machine with none (e.g. a fully isolated runner). Callers skip the
# off-loopback assertion in that case rather than failing on an environment
# fact this feature cannot control.
nonloopback_ipv4() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | grep -v '^127\.' | head -1
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | grep -v '^127\.' | head -1
  fi
}

# tcp_open reports whether a TCP connect to host:port succeeds within a
# couple of seconds. A timeout means "nothing answered" -- refused and
# filtered both take this branch, which is exactly the distinction under test.
tcp_open() {
  local host="$1" port="$2"
  timeout 2 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null
}

# tcp_read connects and returns whatever the peer sends within a couple of
# seconds -- confirms the *right* service answered, not just that some
# listener exists on the port.
tcp_read() {
  local host="$1" port="$2"
  timeout 2 bash -c "exec 3<>/dev/tcp/$host/$port 2>/dev/null; cat <&3" 2>/dev/null || true
}

# tcp_read_retry re-tries tcp_read for a few seconds. The control file
# appearing only means booth--expose wrote it -- the host-side watcher
# polls .booth/.tmp/tcp-tunnels/ once a second (tcp_tunnel.go), so the
# listener itself can still be a beat behind.
tcp_read_retry() {
  local host="$1" port="$2" resp
  for _ in $(seq 1 6); do
    resp="$(tcp_read "$host" "$port")"
    [ -n "$resp" ] && break
    sleep 1
  done
  echo "$resp"
}

wait_for_container() {
  local name="$1"
  for _ in $(seq 1 20); do
    docker exec "$name" bash -lc true >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

wait_for_control_file() {
  local port="$1" tries="${2:-10}"
  for _ in $(seq 1 "$tries"); do
    [ -f ".booth/.tmp/tcp-tunnels/$port" ] && return 0
    sleep 1
  done
  return 1
}

HOST_IP="$(nonloopback_ipv4)"
if [ -z "$HOST_IP" ]; then
  echo "NOTE: no non-loopback IPv4 address on this host; off-loopback checks will be skipped." >&2
fi

# -----------------------------------------------------------------------------
# Case 1: default booth (no --public) -- the tunnel must stay on loopback.
# -----------------------------------------------------------------------------
PRIVATE_PORT="$(pick_free_port)"
EXPOSE_PORT_PRIV="$(pick_free_port_other_than "$PRIVATE_PORT")"

"$BOOTH_BIN" --variant base --name "$NAME_PRIVATE" --port "$PRIVATE_PORT" \
  --keep-alive --no-browser -- 'sleep 300' \
  >"/tmp/test-tunpub-priv-$SUFFIX.log" 2>&1 &
PID_PRIVATE=$!

if ! wait_for_container "$NAME_PRIVATE"; then
  print_test_result "false" "$0" "1" "default booth should come up"
  FAILED=$((FAILED + 1))
  tail -20 "/tmp/test-tunpub-priv-$SUFFIX.log" | sed 's/^/  /'
else
  docker exec -d --user coder "$NAME_PRIVATE" bash -lc \
    "socat TCP-LISTEN:$EXPOSE_PORT_PRIV,bind=127.0.0.1,reuseaddr,fork EXEC:'echo tunnel-priv-ok' >/dev/null 2>&1"
  sleep 1
  EXPOSE_OUTPUT="$(docker exec --user coder "$NAME_PRIVATE" bash -lc "booth--expose $EXPOSE_PORT_PRIV" 2>&1)"

  if echo "$EXPOSE_OUTPUT" | grep -q "This booth is public"; then
    print_test_result "false" "$0" "8" "booth--expose should not warn about a non-public booth's tunnel"
    echo "  Output: $EXPOSE_OUTPUT"
    FAILED=$((FAILED + 1))
  else
    print_test_result "true" "$0" "8" "booth--expose stays quiet about a non-public booth's tunnel"
  fi

  if wait_for_control_file "$EXPOSE_PORT_PRIV"; then
    print_test_result "true" "$0" "1" "default booth's tunnel control file appears on host"
  else
    print_test_result "false" "$0" "1" "default booth's tunnel control file should appear on host"
    FAILED=$((FAILED + 1))
  fi

  RESP="$(tcp_read_retry 127.0.0.1 "$EXPOSE_PORT_PRIV")"
  if echo "$RESP" | grep -qF 'tunnel-priv-ok'; then
    print_test_result "true" "$0" "2" "default booth's tunnel is reachable on loopback"
  else
    print_test_result "false" "$0" "2" "default booth's tunnel should be reachable on loopback"
    echo "  Response: $RESP"
    FAILED=$((FAILED + 1))
  fi

  if [ -n "$HOST_IP" ]; then
    if tcp_open "$HOST_IP" "$EXPOSE_PORT_PRIV"; then
      print_test_result "false" "$0" "3" "default booth's tunnel should NOT be reachable off loopback"
      FAILED=$((FAILED + 1))
    else
      print_test_result "true" "$0" "3" "default booth's tunnel stays off a non-loopback address ($HOST_IP)"
    fi
  else
    echo "SKIP: test 3 (no non-loopback address available)" >&2
  fi
fi

run_coding_booth remove --force --name "$NAME_PRIVATE" >/dev/null 2>&1 || true
kill "$PID_PRIVATE" >/dev/null 2>&1 || true
wait "$PID_PRIVATE" 2>/dev/null || true
PID_PRIVATE=""
reset_booth_tmp

# -----------------------------------------------------------------------------
# Case 2: --public booth -- the tunnel must bind to every interface, the same
# as the booth's own published port.
# -----------------------------------------------------------------------------
echo -n "test-tunnel-public-bind" >.booth/.booth.password
chmod 600 .booth/.booth.password

PUBLIC_PORT="$(pick_free_port_other_than "$PRIVATE_PORT" "$EXPOSE_PORT_PRIV")"
EXPOSE_PORT_PUB="$(pick_free_port_other_than "$PRIVATE_PORT" "$EXPOSE_PORT_PRIV" "$PUBLIC_PORT")"

"$BOOTH_BIN" --variant base --name "$NAME_PUBLIC" --port "$PUBLIC_PORT" --public \
  --keep-alive --no-browser -- 'sleep 300' \
  >"/tmp/test-tunpub-pub-$SUFFIX.log" 2>&1 &
PID_PUBLIC=$!

if ! wait_for_container "$NAME_PUBLIC"; then
  print_test_result "false" "$0" "4" "--public booth should come up"
  FAILED=$((FAILED + 1))
  tail -20 "/tmp/test-tunpub-pub-$SUFFIX.log" | sed 's/^/  /'
else
  docker exec -d --user coder "$NAME_PUBLIC" bash -lc \
    "socat TCP-LISTEN:$EXPOSE_PORT_PUB,bind=127.0.0.1,reuseaddr,fork EXEC:'echo tunnel-pub-ok' >/dev/null 2>&1"
  sleep 1

  # booth--expose refuses on a public booth without --ok-public: the tunnel
  # would have no password or TLS of its own, unlike the booth's own port.
  REFUSE_RC=0
  REFUSE_OUTPUT="$(docker exec --user coder "$NAME_PUBLIC" bash -lc "booth--expose $EXPOSE_PORT_PUB" 2>&1)" || REFUSE_RC=$?
  if [ "$REFUSE_RC" -ne 0 ] && echo "$REFUSE_OUTPUT" | grep -q -- "--ok-public" && ! wait_for_control_file "$EXPOSE_PORT_PUB" 2; then
    print_test_result "true" "$0" "7" "booth--expose refuses on a public booth without --ok-public"
  else
    print_test_result "false" "$0" "7" "booth--expose should refuse on a public booth without --ok-public"
    echo "  Exit: $REFUSE_RC  Output: $REFUSE_OUTPUT"
    FAILED=$((FAILED + 1))
  fi

  # With --ok-public it proceeds -- and still warns, since acknowledging the
  # tradeoff is not the same as making it invisible.
  EXPOSE_OUTPUT="$(docker exec --user coder "$NAME_PUBLIC" bash -lc "booth--expose $EXPOSE_PORT_PUB --ok-public" 2>&1)"
  if echo "$EXPOSE_OUTPUT" | grep -q "This booth is public"; then
    print_test_result "true" "$0" "7b" "booth--expose --ok-public proceeds and still warns"
  else
    print_test_result "false" "$0" "7b" "booth--expose --ok-public should proceed and still warn"
    echo "  Output: $EXPOSE_OUTPUT"
    FAILED=$((FAILED + 1))
  fi

  if wait_for_control_file "$EXPOSE_PORT_PUB"; then
    print_test_result "true" "$0" "4" "--public booth's tunnel control file appears on host"
  else
    print_test_result "false" "$0" "4" "--public booth's tunnel control file should appear on host"
    FAILED=$((FAILED + 1))
  fi

  RESP="$(tcp_read_retry 127.0.0.1 "$EXPOSE_PORT_PUB")"
  if echo "$RESP" | grep -qF 'tunnel-pub-ok'; then
    print_test_result "true" "$0" "5" "--public booth's tunnel is still reachable on loopback"
  else
    print_test_result "false" "$0" "5" "--public booth's tunnel should still be reachable on loopback"
    echo "  Response: $RESP"
    FAILED=$((FAILED + 1))
  fi

  if [ -n "$HOST_IP" ]; then
    RESP="$(tcp_read "$HOST_IP" "$EXPOSE_PORT_PUB")"
    if echo "$RESP" | grep -qF 'tunnel-pub-ok'; then
      print_test_result "true" "$0" "6" "--public booth's tunnel is reachable off loopback ($HOST_IP)"
    else
      print_test_result "false" "$0" "6" "--public booth's tunnel should be reachable off loopback ($HOST_IP)"
      echo "  Response: $RESP"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "SKIP: test 6 (no non-loopback address available)" >&2
  fi
fi

exit $FAILED
