#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: jetbrains-first-run--setup.sh
#
# Runs the real script against a fake JetBrains IDE and asserts the three files it
# seeds. Every expected value here was read back out of an IDE clicked through by
# hand (IDEA IC 2025.2.3) — if one of these assertions starts failing after an IDE
# upgrade, re-measure rather than adjusting the expectation to match the code.
#
# Locked in here:
#   - THIRD_PARTY_PLUGINS_ALLOWED in the IDE's own updates.xml
#   - the workspace path, and ONLY that path, in trusted-paths.xml
#   - data sharing recorded as declined (the third field is 0, not 1)
#   - the EULA is NOT answered — that dialog stays for a human, deliberately
#   - no JetBrains IDE is a skip, not a failure
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
FR_SCRIPT="$SETUPS_DIR/jetbrains-first-run--setup.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: needs jq, which jetbrains-first-run--setup.sh relies on"
    exit 0
fi

ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy the script's root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/opt" "$STUB/empty-opt" "$STUB/seed"

IDE_DIR="$STUB/opt/idea-IC-9.9.9"
mkdir -p "$IDE_DIR/bin"
cat > "$IDE_DIR/product-info.json" << 'EOF'
{ "productCode": "IC", "buildNumber": "999.1.1", "dataDirectoryName": "IdeaICTest" }
EOF
: > "$IDE_DIR/bin/idea.properties"
printf '#!/bin/bash\nexit 0\n' > "$IDE_DIR/idea-starter"
chmod +x "$IDE_DIR/idea-starter"

OPTIONS="$STUB/seed/.config/JetBrains/IdeaICTest/options"
CONSENT="$STUB/seed/.local/share/JetBrains/consentOptions/accepted"

run_first_run() {
    HOME="$STUB/roothome" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    JETBRAINS_OPT_ROOT="${1:-$STUB/opt}" \
    HOME_SEED_DIR="$STUB/seed" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$FR_SCRIPT" ${2+"$2"} < /dev/null 2>&1
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

OUT=$(run_first_run) && RC=0 || RC=$?
check "the setup exits 0" "$([ $RC -eq 0 ] && echo true || echo false)" "$OUT"

# --- Third-Party Plugins Notice ----------------------------------------------
check "updates.xml is seeded" "$([ -f "$OPTIONS/updates.xml" ] && echo true || echo false)"
check "third-party plugins are allowed" \
      "$(grep -qF 'name="THIRD_PARTY_PLUGINS_ALLOWED" value="true"' "$OPTIONS/updates.xml" \
         && echo true || echo false)" "$(cat "$OPTIONS/updates.xml" 2>/dev/null)"
check "it is written under the component the IDE reads" \
      "$(grep -qF 'component name="UpdatesConfigurable"' "$OPTIONS/updates.xml" \
         && echo true || echo false)"

# --- Trust and Open Project ---------------------------------------------------
check "trusted-paths.xml is seeded" "$([ -f "$OPTIONS/trusted-paths.xml" ] && echo true || echo false)"
check "the workspace path is trusted" \
      "$(grep -qF '<entry key="$USER_HOME$/code" value="true" />' "$OPTIONS/trusted-paths.xml" \
         && echo true || echo false)" "$(cat "$OPTIONS/trusted-paths.xml" 2>/dev/null)"
# Trusting the parent would trust every project ever opened from the home dir, which is
# the checkbox on that dialog and precisely what must not be seeded.
check "only that path is trusted — one entry, no parent dir" \
      "$([ "$(grep -c '<entry key=' "$OPTIONS/trusted-paths.xml")" = "1" ] \
         && ! grep -qF '<entry key="$USER_HOME$" ' "$OPTIONS/trusted-paths.xml" \
         && echo true || echo false)"

OUT=$(run_first_run "$STUB/opt" '$USER_HOME$/work') && RC=0 || RC=$?
check "the trusted path is overridable" \
      "$(grep -qF '<entry key="$USER_HOME$/work" value="true" />' "$OPTIONS/trusted-paths.xml" \
         && echo true || echo false)" "$(cat "$OPTIONS/trusted-paths.xml" 2>/dev/null)"

# --- Data Sharing -------------------------------------------------------------
run_first_run > /dev/null 2>&1
check "consent file is seeded" "$([ -f "$CONSENT" ] && echo true || echo false)"
check "data sharing is DECLINED, not accepted" \
      "$(grep -qE '^rsch\.send\.usage\.stat:1\.1:0:[0-9]+$' "$CONSENT" && echo true || echo false)" \
      "$(cat "$CONSENT" 2>/dev/null)"

# --- The EULA is deliberately untouched ---------------------------------------
# Accepting a licence for someone at build time is a legal act, not a default. If this
# assertion ever fails, that decision was reversed — make sure it was on purpose.
check "no EULA acceptance is written" \
      "$(grep -rqi "eua\|accepted_version" "$STUB/seed" 2>/dev/null && echo false || echo true)" \
      "$(grep -ril "eua\|accepted_version" "$STUB/seed" 2>/dev/null)"

# --- Skip ---------------------------------------------------------------------
OUT=$(run_first_run "$STUB/empty-opt") && RC=0 || RC=$?
check "no JetBrains IDE is a skip, not a failure" \
      "$([ $RC -eq 0 ] && echo "$OUT" | grep -qF "no JetBrains IDE installed" && echo true || echo false)" "$OUT"

if [ "$ALL_PASSED" != "true" ]; then
    exit 1
fi
