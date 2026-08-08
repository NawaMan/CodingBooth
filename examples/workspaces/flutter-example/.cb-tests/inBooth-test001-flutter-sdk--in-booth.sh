#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The Flutter SDK is present, runnable, and writable — from a NON-LOGIN shell.
#
# The non-login part is the point: `booth -- ./script.sh` runs via
# `runuser -u coder --`, which never sources /etc/profile.d. A setup that only
# wires PATH through profile.d looks fine interactively and fails in every
# script, so this test deliberately does not use `bash -l`.

set -euo pipefail

echo "=== Flutter and Dart on a non-login shell ==="

FAILED=0

for tool in flutter dart; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✅ $tool -> $(command -v "$tool")"
    else
        echo "  ❌ $tool NOT on PATH"
        FAILED=1
    fi
done

echo ""
echo "=== flutter runs (proves git accepts the root-owned SDK checkout) ==="
# The SDK ships as a git checkout. Owned by root and run as coder, git refuses
# it with "detected dubious ownership" and the tool dies here rather than
# printing a version — which is why this is an assertion and not a nicety.
#
# Run under `timeout`, capturing output to a file rather than piping it: flutter
# regenerates bin/cache/engine.stamp on startup with `mv`, and if that file is
# not writable `mv` asks "overriding mode 0644?" and waits on a stdin that never
# answers. Piped straight into a grep the question is invisible, and the test
# just stops — no output, no failure, forever. `</dev/null` makes the prompt
# fail instead of block, and the timeout is the backstop.
VERSION_OUT="$(mktemp)"
if timeout 120 flutter --version </dev/null > "$VERSION_OUT" 2>&1; then
    RC=0
else
    RC=$?
fi

if [[ $RC -eq 124 ]]; then
    echo "  ❌ flutter --version timed out after 120s (it is blocked, not slow)"
    echo "  --- output up to the stall ---"
    sed 's/^/      /' "$VERSION_OUT"
    echo "  --- bin/cache permissions ---"
    ls -la "${FLUTTER_ROOT:-/usr/local/flutter-current}/bin/cache" | sed 's/^/      /'
    FAILED=1
elif grep -qiE "^Flutter [0-9]+\.[0-9]+" "$VERSION_OUT"; then
    grep -m1 -iE "^Flutter [0-9]+\.[0-9]+" "$VERSION_OUT"
else
    echo "  ❌ flutter did not report a version (exit $RC)"
    sed 's/^/      /' "$VERSION_OUT" | head -n 10
    FAILED=1
fi
rm -f "$VERSION_OUT"

echo ""
echo "=== dart compiles and runs a program ==="
# Not a --version check: this makes the bundled Dart SDK actually do the work.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/sum.dart" <<'DART'
void main() {
  final total = [1, 2, 3, 4, 5].fold<int>(0, (a, b) => a + b);
  print('SUM=$total');
}
DART
if dart run "$WORK/sum.dart" 2>/dev/null | grep -q "SUM=15"; then
    echo "  ✅ dart ran a program and produced the right answer"
else
    echo "  ❌ dart failed to run a program"
    dart run "$WORK/sum.dart" || true
    FAILED=1
fi

echo ""
echo "=== the SDK cache is writable by the booth user ==="
# booth-entry remaps coder's UID to the host user's, so a build-time `chown`
# would only match by luck. The setup uses mode bits instead; this is the check
# that the choice actually holds on this host.
CACHE="${FLUTTER_ROOT:-/usr/local/flutter-current}/bin/cache"
if [[ -w "$CACHE" ]]; then
    echo "  ✅ $CACHE writable as $(id -un) (uid $(id -u))"
else
    echo "  ❌ $CACHE not writable as $(id -un) (uid $(id -u))"
    ls -ld "$CACHE" || true
    FAILED=1
fi

exit $FAILED
