#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Pair and connect to a real Android device over Wi-Fi debugging (Android 11+),
# so adb install / logcat / debugging work without an emulator — the emulator
# does not run under Docker Desktop's amd64 emulation on Apple Silicon (see the
# README's Architecture note), but a real device over the network is unaffected.
#
# Run this INSIDE the booth: ../../../codingbooth -- ./device-connect.sh ...
#
# On the phone: Settings -> Developer options -> Wireless debugging ->
# "Pair device with pairing code" shows the IP, a PAIRING port, and a 6-digit
# code. The Wireless debugging screen itself (not the pairing dialog) shows a
# second, separate CONNECT port for the same IP — that is what adb connect
# uses afterward. The two ports are normally different.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 <ip> <pairing-port> <pairing-code> [connect-port]

Example:
  $0 192.168.1.42 37831 482913 5555

If <connect-port> is omitted, this only pairs; run
  adb connect <ip>:<connect-port>
by hand afterward with the port shown on the phone's Wireless debugging screen.
USAGE
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

IP="$1"
PAIR_PORT="$2"
CODE="$3"
CONNECT_PORT="${4:-}"

if ! command -v adb >/dev/null 2>&1; then
  echo "❌ adb not found on PATH. Is this running inside the booth?" >&2
  echo "   Try: ../../../codingbooth -- ./device-connect.sh ..." >&2
  exit 1
fi

echo "=== Pairing with $IP:$PAIR_PORT ==="
if ! adb pair "$IP:$PAIR_PORT" "$CODE"; then
  echo "❌ Pairing failed. The pairing code/port are one-time — re-open" >&2
  echo "   'Pair device with pairing code' on the phone for a fresh pair." >&2
  exit 1
fi

if [[ -z "$CONNECT_PORT" ]]; then
  echo ""
  echo "Paired. No connect-port given, so skipping adb connect."
  echo "Run:  adb connect $IP:<connect-port>"
  echo "using the port shown on the phone's main Wireless debugging screen."
  exit 0
fi

echo ""
echo "=== Connecting to $IP:$CONNECT_PORT ==="
if ! adb connect "$IP:$CONNECT_PORT"; then
  echo "❌ Connect failed. Check that the phone and this booth's host are on" >&2
  echo "   the same Wi-Fi, and that the connect port is still current." >&2
  exit 1
fi

echo ""
echo "=== Devices ==="
adb devices
echo ""
echo "Look for '$IP:$CONNECT_PORT   device' above — 'unauthorized' means"
echo "you still need to accept the debugging prompt on the phone's screen."
