#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: `setup flutter` installs a Flutter SDK that actually compiles.
#
# Three failure modes this is built around, none of which a `--version` grep
# would catch:
#
#  1. The SDK ships as a git checkout. Installed by root and run by coder, git
#     refuses it with "detected dubious ownership" and the flutter tool dies
#     before it does anything. The setup's `git config --system --add
#     safe.directory` is the fix, and test 3 is what proves it.
#
#  2. The tool writes back into its own tree (bin/cache) at runtime. `chown
#     coder` is the wrong fix, because booth-entry remaps coder's UID to the
#     host user's at container start — so a build-time owner only matches by
#     luck, and the failure appears on some hosts and not others. Test 5 checks
#     the mode bits, which are UID-agnostic.
#
#  3. profile.d is not read by `booth -- cmd`, so anything wired only through
#     the profile is missing from every script. Test 4 runs in that shell.
#
# Test 1 is docker-free. Tests 2+ build a real image; the setup script is copied
# into .booth/setups/ so this runs against the released base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: setup flutter builds and runs Dart/Flutter code ==="

FAILED=0

BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

# Test 1: flutter compiles to a RUN of its setup script, with its arg intact.
if echo "$DOCKERFILE" | grep -qE "RUN flutter--setup\.sh --version latest" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown setup script 'flutter'"; then
    print_test_result "true" "$0" "1" "setup flutter compiles to RUN flutter--setup.sh"
else
    print_test_result "false" "$0" "1" "setup flutter should compile to RUN flutter--setup.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# Test 2: the copy under .booth/setups/ has not drifted from the repo's. The
# copy is what actually runs, so a drift means this suite verifies a script that
# is not the one being shipped.
REPO_SCRIPT="$CHECK_DIR/variants/base/setups/flutter--setup.sh"
LOCAL_SCRIPT="$SCRIPT_DIR/.booth/setups/flutter--setup.sh"
if [[ -f "$REPO_SCRIPT" ]] && diff -q "$REPO_SCRIPT" "$LOCAL_SCRIPT" >/dev/null 2>&1; then
    print_test_result "true" "$0" "2" ".booth/setups copy matches variants/base/setups"
else
    print_test_result "false" "$0" "2" ".booth/setups copy should match variants/base/setups"
    echo "  Compared: $REPO_SCRIPT <-> $LOCAL_SCRIPT"
    FAILED=$((FAILED + 1))
fi

# The remaining tests build a real image. The setup script is copied into
# .booth/setups/ so it does not need to be baked into the base image, but the
# base image itself still has to resolve — skip (reporting the emit results)
# when no local one is tagged.
use_local_base_image || exit $FAILED

# flutter--setup.sh gates itself on amd64 — Google publishes the Linux SDK for
# x86_64 only (dart_sdk_arch is "x64" and there has never been a linux-arm64
# stable build), so on arm64 it warns and installs nothing by design. flutter and
# dart are then legitimately absent, so skip rather than report a failure for a
# documented no-op.
SERVER_ARCH="$(docker_server_arch)"
if [[ "$SERVER_ARCH" != "amd64" ]]; then
    echo "SKIP: Flutter's Linux SDK is published for x86_64 only; docker builds for '${SERVER_ARCH}' here." >&2
    exit $FAILED
fi

# Test 3: dart compiles and runs a program. This is the functional bar: a Dart
# SDK that landed on PATH but cannot read its own snapshot, or a flutter tool
# git refuses to look at, both pass `command -v` and fail here.
#
# The program is a file in this directory, not a string passed in: `booth -- a b
# c` joins its arguments into one string and runs that through a shell, so
# `bash -c "<source>"` arrives with its quoting gone and silently runs something
# else. Everything below is a single pre-joined string for the same reason.
ACTUAL=$(run_coding_booth --silence-build -- 'dart run sum.dart' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -q "SUM=15"; then
    print_test_result "true" "$0" "3" "dart compiles and runs a program"
else
    print_test_result "false" "$0" "3" "dart should compile and run a program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: flutter and dart resolve in a NON-LOGIN shell — the shell
# `booth -- ./build.sh` actually gets, which never sources /etc/profile.d.
ACTUAL=$(run_coding_booth --silence-build -- 'command -v flutter && command -v dart' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -q "flutter" && echo "$ACTUAL" | grep -q "dart"; then
    print_test_result "true" "$0" "4" "flutter and dart are on PATH in a non-login shell"
else
    print_test_result "false" "$0" "4" "flutter and dart should be on PATH in a non-login shell"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: the SDK cache is writable by the booth user, whatever UID it was
# remapped to. Read-only here turns the first real command into a permission
# error on exactly the hosts where the build-time UID did not match.
ACTUAL=$(run_coding_booth --silence-build -- \
    'test -w /usr/local/flutter-current/bin/cache && echo WRITABLE' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "WRITABLE" ]]; then
    print_test_result "true" "$0" "5" "the SDK cache is writable by the booth user"
else
    print_test_result "false" "$0" "5" "the SDK cache should be writable by the booth user"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 6: the flutter tool itself runs and reports its version. This is what
# breaks on "dubious ownership" — the tool shells out to git against its own
# checkout to work out which version it is.
#
# Under `timeout` and with stdin closed: flutter rewrites bin/cache/engine.stamp
# with `mv` on startup, and against an unwritable target `mv` prompts and waits
# on stdin forever. Without these guards the whole suite stops here with no
# output rather than failing.
ACTUAL=$(run_coding_booth --silence-build -- 'timeout 120 flutter --version </dev/null 2>&1' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE "^Flutter [0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "6" "flutter reports its version (git ownership is accepted)"
else
    print_test_result "false" "$0" "6" "flutter should report its version"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 7: Flutter compiles a real app for the web. The heaviest assertion and
# the most meaningful one — it exercises the Dart compiler, the web engine
# artifacts the setup precached, and the cache directory being writable, all at
# once. A booth that passes tests 3-6 and fails this one is not usable.
ACTUAL=$(run_coding_booth --silence-build -- 'cd /tmp && rm -rf webapp && flutter create --platforms=web webapp >/dev/null 2>&1 && cd webapp && flutter build web >/dev/null 2>&1 && test -s build/web/main.dart.js && echo BUILT' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "BUILT" ]]; then
    print_test_result "true" "$0" "7" "flutter builds a web app to main.dart.js"
else
    print_test_result "false" "$0" "7" "flutter should build a web app to main.dart.js"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
