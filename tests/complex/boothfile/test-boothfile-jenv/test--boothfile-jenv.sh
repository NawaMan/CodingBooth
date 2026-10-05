#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: jenv and the JDK agree on JAVA_HOME
#
# `java:21+jenv`. jenv's profile used to sort before the JDK's (57 < 60), so the
# JDK profile overwrote the JAVA_HOME jenv chose in every non-interactive shell
# (`booth -- mvn ...`), while `java` itself followed jenv. Moving jenv after the
# JDK exposed the other half: with no version chosen, jenv's export hook sets
# JAVA_HOME="", which the profile now falls back from to the booth's JDK.
#
# One booth, one probe (probe-java-home.sh), four shells asserted:
#   no version chosen  x  non-interactive / interactive  ->  JAVA_HOME is JDK 21
#   jenv global 21     x  non-interactive / interactive  ->  JAVA_HOME is JDK 21,
#     although a second JDK (17) installed afterwards owns the JDK profile.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: jenv and the JDK agree on JAVA_HOME ==="

FAILED=0

OUT=$(run_coding_booth --silence-build -- bash /home/coder/code/probe-java-home.sh 2>/dev/null) || OUT=""

value_of() { printf '%s\n' "$OUT" | grep -oE "(^| )$1=[^ ]*" | head -1 | sed -E "s/^ ?$1=//"; }

check() {
    local num="$1" key="$2" expected="$3" desc="$4"
    local actual
    actual="$(value_of "$key")"
    if [[ "$actual" == "$expected" ]]; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "  $key: expected '$expected', got '$actual' (JAVA_HOME='$(value_of "${key}_RAW")')"
        FAILED=$((FAILED + 1))
    fi
}

check 1 NI_SYSTEM      21 "no jenv version: non-interactive JAVA_HOME is the booth's JDK"
check 2 IA_SYSTEM      21 "no jenv version: interactive JAVA_HOME is the booth's JDK"

# The rest needs the second JDK and the jenv choice to have landed.
if [[ "$(value_of JDK17_RC)" != "0" || "$(value_of JENV_GLOBAL)" != "21" ]]; then
    print_test_result "false" "$0" "3" "second JDK installed and jenv global set to 21"
    echo "  JDK17_RC='$(value_of JDK17_RC)' JENV_GLOBAL='$(value_of JENV_GLOBAL)'"
    echo "$OUT" | tail -20
    exit $((FAILED + 1))
fi
print_test_result "true" "$0" "3" "second JDK installed and jenv global set to 21"

check 4 NI_CHOSEN_PATH 21 "jenv global 21: java on PATH is 21"
check 5 NI_CHOSEN      21 "jenv global 21: non-interactive JAVA_HOME follows jenv"
check 6 IA_CHOSEN      21 "jenv global 21: interactive JAVA_HOME follows jenv"

exit $FAILED
