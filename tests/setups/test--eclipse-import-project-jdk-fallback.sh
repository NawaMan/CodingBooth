#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: eclipse-import-project--setup.sh's compiler-JDK fallback
#
# Application.java is compiled against Eclipse's own resource/runtime jars,
# which are class file version 61+ (Java 17+) regardless of JDK_VERSION -- the
# project's own selected JDK, which can legitimately be much older (8, 11,
# ...). Reusing that javac to read Eclipse's jars used to fail with "bad
# class file ... has wrong version". The fix downloads a throwaway JDK 21
# for just this one compile step when the system javac is too old, and
# otherwise leaves it alone. This test locks in both branches:
#
#   1. a too-old javac (<17) triggers the download and the compiler JDK's own
#      javac -- not the system one -- is what actually compiles
#   2. a new-enough javac (>=17) compiles directly, with no download at all
#   3. the throwaway JDK directory is cleaned up afterwards either way
#
# javac, curl and tar are stubbed, so nothing is downloaded and no real
# bytecode is produced.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/eclipse-import-project--setup.sh"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin"

# The fallback block, lifted out of the setup script so the surrounding
# Eclipse-dir discovery and plugin scaffolding do not have to run.
sed -n '/^JAVAC_BIN="javac"$/,/^\[\[ -n "\$COMPILER_JDK_DIR" \]\] && rm -rf "\$COMPILER_JDK_DIR"$/p' \
  "$SETUP_SCRIPT" > "$STUB/fn.sh"

if [ ! -s "$STUB/fn.sh" ]; then
  print_test_result "false" "$0" "1" "the compiler-JDK fallback block should be extractable"
  echo "  Looked in: $SETUP_SCRIPT"
  exit 1
fi

# --- Stubs -------------------------------------------------------------------
# System javac: reports $SYS_JAVAC_VERSION for -version, otherwise records the
# compile invocation.
cat > "$STUB/bin/javac" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "-version" ]; then
  echo "javac ${SYS_JAVAC_VERSION}"
  exit 0
fi
echo "SYSTEM_JAVAC_CALLED $*" >> "$CALL_LOG"
exit 0
EOF

# curl: records the download URL and drops a fake archive in its place.
cat > "$STUB/bin/curl" << 'EOF'
#!/bin/bash
echo "CURL_CALLED $*" >> "$CALL_LOG"
args=("$@")
for i in "${!args[@]}"; do
  if [ "${args[$i]}" = "-o" ]; then
    : > "${args[$((i+1))]}"
  fi
done
exit 0
EOF

# tar: instead of really extracting, drops a fake compiler-JDK javac that
# records its own invocation, distinct from the system stub above.
cat > "$STUB/bin/tar" << 'EOF'
#!/bin/bash
dest=""
prev=""
for a in "$@"; do
  [ "$prev" = "-C" ] && dest="$a"
  prev="$a"
done
mkdir -p "$dest/bin"
cat > "$dest/bin/javac" << 'INNEREOF'
#!/bin/bash
echo "COMPILER_JDK_JAVAC_CALLED $*" >> "$CALL_LOG"
exit 0
INNEREOF
chmod +x "$dest/bin/javac"
exit 0
EOF
chmod +x "$STUB/bin/javac" "$STUB/bin/curl" "$STUB/bin/tar"

run_fallback() {
  CALL_LOG="$STUB/calls.log"
  : > "$CALL_LOG"
  WORK="$STUB/work"
  rm -rf "$WORK/src" "$WORK/build"
  mkdir -p "$WORK/src/cb/importproject" "$WORK/build"
  : > "$WORK/src/cb/importproject/Application.java"

  PATH="$STUB/bin:/usr/bin:/bin" \
  SYS_JAVAC_VERSION="$1" \
  CALL_LOG="$CALL_LOG" \
  WORK="$WORK" \
  CP="dummy.jar" \
    bash -c "export CALL_LOG WORK CP; source '$STUB/fn.sh'; echo \"COMPILER_JDK_DIR=\$COMPILER_JDK_DIR\""
}

ALL_PASSED=true

# --- Test 1: a too-old javac triggers the compiler-JDK download --------------
OUT_OLD="$(run_fallback '11.0.2')"
CALLS_OLD="$(cat "$STUB/calls.log")"

if echo "$CALLS_OLD" | grep -qF 'CURL_CALLED' \
   && echo "$CALLS_OLD" | grep -qF '/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse'; then
  print_test_result "true" "$0" "1" "javac 11 fetches a JDK 21 compiler for linux/x64"
else
  print_test_result "false" "$0" "1" "javac 11 should fetch the JDK 21 x64 build"
  echo "  Calls: $CALLS_OLD"
  ALL_PASSED=false
fi

# --- Test 2: the compile itself runs through the downloaded compiler ---------
if echo "$CALLS_OLD" | grep -qF 'COMPILER_JDK_JAVAC_CALLED' \
   && ! echo "$CALLS_OLD" | grep -qF 'SYSTEM_JAVAC_CALLED'; then
  print_test_result "true" "$0" "2" "compile runs through the downloaded compiler JDK, not the system one"
else
  print_test_result "false" "$0" "2" "compile should use the compiler JDK's javac, not the system one"
  echo "  Calls: $CALLS_OLD"
  ALL_PASSED=false
fi

# --- Test 3: the throwaway JDK dir is removed afterwards ---------------------
COMPILER_DIR_OLD="$(echo "$OUT_OLD" | sed -n 's/^COMPILER_JDK_DIR=//p')"
if [ -n "$COMPILER_DIR_OLD" ] && [ ! -e "$COMPILER_DIR_OLD" ]; then
  print_test_result "true" "$0" "3" "the throwaway compiler JDK is cleaned up after the compile"
else
  print_test_result "false" "$0" "3" "the throwaway compiler JDK dir should not survive the compile step"
  echo "  Dir: ${COMPILER_DIR_OLD:-<empty>}"
  ALL_PASSED=false
fi

# --- Test 4: a new-enough javac compiles directly, no download at all --------
OUT_NEW="$(run_fallback '21.0.1')"
CALLS_NEW="$(cat "$STUB/calls.log")"

if ! echo "$CALLS_NEW" | grep -qF 'CURL_CALLED' \
   && echo "$CALLS_NEW" | grep -qF 'SYSTEM_JAVAC_CALLED'; then
  print_test_result "true" "$0" "4" "javac 21 compiles directly with no compiler-JDK download"
else
  print_test_result "false" "$0" "4" "javac 21 should compile without downloading anything"
  echo "  Calls: $CALLS_NEW"
  ALL_PASSED=false
fi

[ "$ALL_PASSED" = true ]
