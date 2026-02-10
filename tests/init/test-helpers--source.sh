#!/bin/bash
# Shared test helpers for init tests.
# This file is meant to be sourced, not executed directly.
# Usage: source "$(dirname "$0")/test-helpers--source.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This file should be sourced, not executed directly." >&2
    echo "Usage: source \"\$(dirname \"\$0\")/test-helpers--source.sh\"" >&2
    exit 1
fi

testname=$(basename "$0" .sh)
prj="$(pwd)/prj--${testname}"
log="$(pwd)/log--${testname}.log"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

VERBOSE=false
for arg in "$@"; do case "$arg" in --verbose) VERBOSE=true ;; esac ;done

function booth() {
    local dir
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/templates" ]]; then
            CB_TEMPLATES_PATH="$dir/templates" \
            "$dir/codingbooth" "$@"
            return
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: templates directory not found" >&2
    return 1
}

function run() {
    echo "" >> $log
    echo "> $*" >> $log
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  > $*"
    fi

    "$@" >> $log 2>&1
}

function booth-collect() {
    local cmd="$1"
    cd $prj
    booth --silence-build -- "$cmd" > "$tmpfile"
    cd ..
    cat "$tmpfile" >> $log
    if [[ "$VERBOSE" == "true" ]]; then
        cat "$tmpfile"
    fi
}

function booth-collect-dind() {
    local cmd="$1"
    cd $prj
    booth --silence-build --dind -- "$cmd" > "$tmpfile"
    cd ..
    cat "$tmpfile" >> $log
    if [[ "$VERBOSE" == "true" ]]; then
        cat "$tmpfile"
    fi
}

function assert-line() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi

    TEST_COUNT=$((TEST_COUNT + 1))

    local FILE="${1}"
    local PREFIX="${2}"
    local EXPECTED="${3}"
    local MESSAGE="${4}"
    echo "" >> $log
    local width=64
    local label="${MESSAGE} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')

    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad}"
    if [[ "$VERBOSE" == "true" ]]; then echo ""; else echo -n " "; fi

    echo "## Test ${TEST_COUNT} ###########################" >> $log

    local FOUND
    FOUND="$(grep "^${PREFIX}" "$FILE" 2>/dev/null | head -1)" || true
    echo "  assert-line: prefix='${PREFIX}' found='${FOUND}' expected='${PREFIX}${EXPECTED}'" >> $log

    if [[ "${FOUND}" != "${PREFIX}${EXPECTED}" ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"

        echo "  EXPECTED: ${PREFIX}${EXPECTED}"
        echo "  FOUND   : ${FOUND}"
        return
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
}

function assert-last() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi

    TEST_COUNT=$((TEST_COUNT + 1))

    CMD="${1}"
    EXPECTED="${2}"
    MESSAGE="${3}"
    echo "" >> $log
    local width=64
    local label="${MESSAGE} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')

    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad}"
    if [[ "$VERBOSE" == "true" ]]; then echo ""; else echo -n " "; fi

    echo "## Test ${TEST_COUNT} ###########################" >> $log
    run cd $prj

    run booth -- "${CMD}"
    FOUND="$(tail $log -n 1)"
    if [[ "${FOUND}" != "${EXPECTED}" ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"

        echo "  EXPECTED: $EXPECTED"
        echo "  FOUND   : $FOUND"

        cd ..
        return
    fi
    run cd ..
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
}

function skip() {
    local reason="${1:-No reason given}"
    echo ""
    echo -e "== \033[33mSKIPPED\033[0m ================================================================"
    echo "  ${testname}"
    echo "  Reason: ${reason}"
    echo "==============================================================================="
    echo ""
    exit 2
}

function begin() {
    echo "Begin ${testname}" | tee $log
    run rm -Rf $prj
    mkdir -p "${prj}"
    tmpfile="$(mktemp)" ; echo "Using temp file: $tmpfile" >> $log
}

function finally() {
    rm -f "$tmpfile"
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        echo ""
        echo -e "== \033[31mSOME TEST FAIL\033[0m ============================================================="
        echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
        echo "-------------------------------------------------------------------------------"

        echo ""
        echo "Failed tests:"
        for T in "${FAIL_TESTS[@]}"; do
            echo -e "  \u274c ${T}"
        done

        if [[ "${VERBOSE}" == "true" ]]; then
            echo ""
            echo "= Full log ======================================="
            cat "$log"
            echo "--------------------------------------------------"
        else
            echo ""
            echo "Rerun with --verbose to see the full log."
            echo " OR run"
            echo "cat $log"
        fi

        echo "==============================================================================="
        exit 1
    fi

    echo -e "== \033[32mALL TEST PASS\033[0m =============================================================="
}
