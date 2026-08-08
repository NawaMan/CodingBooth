#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: jetbrains-jdk--setup.sh
#
# Runs the real jetbrains-jdk--setup.sh against a fake /opt/jdk-installs holding
# three JDKs and a fake JetBrains IDE, and asserts the jdk.table.xml it seeds.
#
# Locked in here:
#   - one SDK entry per JDK, named <vendor>-<major> — the name a JetBrains IDE gives
#     a JDK it discovers itself, and the name projects already carry in
#     .idea/misc.xml, so getting it wrong silently leaves the project unresolved
#   - homePath is the install dir, and the version comes from the JDK's release file
#   - Java 9+ gets jrt:// module roots and per-module src.zip source roots
#   - Java 8 gets jar:// roots for jre/lib — it has no module image at all, and an
#     SDK with no class roots looks exactly like no SDK
#   - the table is seeded under the IDE's own dataDirectoryName
#   - the JDKs are also linked into the seed's ~/.jdks, where the IDE looks by itself
#   - no IDE, or no JDK, is a skip rather than a failure
#
# The script requires root; fakeroot satisfies that, and every path it touches is
# redirected into a temp tree.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
JDK_SCRIPT="$SETUPS_DIR/jetbrains-jdk--setup.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: needs jq, which jetbrains-jdk--setup.sh relies on"
    exit 0
fi

ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy jetbrains-jdk--setup.sh's root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/jdks" "$STUB/no-jdks" "$STUB/opt" "$STUB/empty-opt" "$STUB/seed"

# ---- A fake JetBrains IDE ----------------------------------------------------
IDE_DIR="$STUB/opt/idea-IC-9.9.9"
mkdir -p "$IDE_DIR/bin"
cat > "$IDE_DIR/product-info.json" << 'EOF'
{ "productCode": "IC", "buildNumber": "999.1.1", "dataDirectoryName": "IdeaICTest" }
EOF
: > "$IDE_DIR/bin/idea.properties"
printf '#!/bin/bash\nexit 0\n' > "$IDE_DIR/idea-starter"
chmod +x "$IDE_DIR/idea-starter"

# ---- Fake JDKs ---------------------------------------------------------------
# make_modular_jdk <dir-name> <java-version> <modules...>
make_modular_jdk() {
    local dir="$STUB/jdks/$1" ver="$2"; shift 2
    mkdir -p "$dir/bin" "$dir/lib"
    printf 'JAVA_VERSION="%s"\nIMPLEMENTOR="Test"\n' "$ver" > "$dir/release"
    : > "$dir/lib/src.zip"
    {
        echo '#!/bin/bash'
        echo '[[ "${1:-}" == "--list-modules" ]] || exit 2'
        for m in "$@"; do echo "echo '$m@VER'"; done
    } > "$dir/bin/java"
    chmod +x "$dir/bin/java"
}

# Java 8: no module image, so `java --list-modules` fails and the classes are jars.
make_legacy_jdk() {
    local dir="$STUB/jdks/$1" ver="$2"
    mkdir -p "$dir/bin" "$dir/jre/lib/ext"
    printf 'JAVA_VERSION="%s"\nIMPLEMENTOR="Test"\n' "$ver" > "$dir/release"
    : > "$dir/jre/lib/rt.jar"
    : > "$dir/jre/lib/jce.jar"
    : > "$dir/jre/lib/ext/sunjce_provider.jar"
    : > "$dir/src.zip"
    printf '#!/bin/bash\nexit 1\n' > "$dir/bin/java"
    chmod +x "$dir/bin/java"
}

make_modular_jdk 25-temurin  "25.0.4"  java.base java.sql
make_modular_jdk 17-corretto "17.0.13" java.base
make_legacy_jdk  8-temurin   "1.8.0_452"

TABLE="$STUB/seed/.config/JetBrains/IdeaICTest/options/jdk.table.xml"

run_jdk_setup() {
    HOME="$STUB/roothome" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    JETBRAINS_OPT_ROOT="${1:-$STUB/opt}" \
    JDK_INSTALLS_DIR="${2:-$STUB/jdks}" \
    HOME_SEED_DIR="$STUB/seed" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$JDK_SCRIPT" < /dev/null 2>&1
}

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = "true" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [ -n "$detail" ] && echo "$detail" | sed 's/^/          /'
        ALL_PASSED=false
    fi
}

# --- the run itself -----------------------------------------------------------
OUT=$(run_jdk_setup) && RC=0 || RC=$?
check "the setup exits 0" "$([ $RC -eq 0 ] && echo true || echo false)" "$OUT"
check "the table is seeded under the IDE's data dir" \
      "$([ -f "$TABLE" ] && echo true || echo false)" "$(find "$STUB/seed" 2>/dev/null)"

if [ ! -f "$TABLE" ]; then
    echo "no table produced; skipping the rest"
    exit 1
fi

has() { grep -qF -- "$1" "$TABLE"; }

# --- one entry per JDK, named <vendor>-<major> --------------------------------
COUNT=$(grep -c '<jdk version="2">' "$TABLE" || true)
check "one SDK entry per JDK (3)" "$([ "$COUNT" = "3" ] && echo true || echo false)" "found: $COUNT"

check 'SDK named temurin-25'  "$(has '<name value="temurin-25" />'  && echo true || echo false)"
check 'SDK named corretto-17' "$(has '<name value="corretto-17" />' && echo true || echo false)"
check 'SDK named temurin-8'   "$(has '<name value="temurin-8" />'   && echo true || echo false)"

# --- homePath and version -----------------------------------------------------
check "homePath is the install dir" \
      "$(has "<homePath value=\"$STUB/jdks/25-temurin\" />" && echo true || echo false)"
check "version comes from the release file" \
      "$(has 'java version &quot;25.0.4&quot;' && echo true || echo false)"
check "the Java 8 version string is its own" \
      "$(has 'java version &quot;1.8.0_452&quot;' && echo true || echo false)"

# --- Java 9+ roots ------------------------------------------------------------
check "modular JDK gets jrt:// class roots" \
      "$(has "jrt://$STUB/jdks/25-temurin!/java.base" && echo true || echo false)"
check "modular JDK gets per-module source roots" \
      "$(has "jar://$STUB/jdks/25-temurin/lib/src.zip!/java.sql" && echo true || echo false)"

# --- Java 8 roots -------------------------------------------------------------
# The branch the booth itself cannot exercise: with no module image, an SDK built
# the Java 9 way would carry no class roots at all and resolve nothing.
check "Java 8 gets jar:// roots for jre/lib" \
      "$(has "jar://$STUB/jdks/8-temurin/jre/lib/rt.jar!/" && echo true || echo false)"
check "Java 8 picks up jre/lib/ext too" \
      "$(has "jar://$STUB/jdks/8-temurin/jre/lib/ext/sunjce_provider.jar!/" && echo true || echo false)"
check "Java 8 gets its flat src.zip" \
      "$(has "jar://$STUB/jdks/8-temurin/src.zip!/" && echo true || echo false)"
check "Java 8 gets no jrt:// root" \
      "$(grep -qF "jrt://$STUB/jdks/8-temurin" "$TABLE" && echo false || echo true)"

# --- ~/.jdks links ------------------------------------------------------------
check "JDKs are linked into the seed's ~/.jdks" \
      "$([ -L "$STUB/seed/.jdks/temurin-25" ] && [ -L "$STUB/seed/.jdks/temurin-8" ] \
         && echo true || echo false)" "$(ls -l "$STUB/seed/.jdks" 2>&1)"

# --- skips --------------------------------------------------------------------
# Both halves are optional on their own: `setup idea` with no Java is a fine Kotlin
# booth, and `setup jdk` on a non-desktop variant is the common case.
OUT=$(run_jdk_setup "$STUB/empty-opt") && RC=0 || RC=$?
check "no JetBrains IDE is a skip, not a failure" \
      "$([ $RC -eq 0 ] && echo "$OUT" | grep -qF "no JetBrains IDE installed" && echo true || echo false)" "$OUT"

OUT=$(run_jdk_setup "$STUB/opt" "$STUB/no-jdks") && RC=0 || RC=$?
check "no JDK is a skip, not a failure" \
      "$([ $RC -eq 0 ] && echo "$OUT" | grep -qF "no JDK under" && echo true || echo false)" "$OUT"

if [ "$ALL_PASSED" != "true" ]; then
    exit 1
fi
