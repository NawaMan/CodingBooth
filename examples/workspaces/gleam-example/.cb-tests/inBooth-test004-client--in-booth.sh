#!/bin/bash
echo "=== Testing the CLI client against the running server ==="
cd "$(dirname "$0")/.."
trap 'just stop >/dev/null 2>&1' EXIT

just start >/dev/null || exit 1

fail=0
expect() {  # <description> <expected exit> <expected substring> <client args...>
    local what="$1" want_exit="$2" want="$3"; shift 3
    local got code
    got="$(just client "$@" 2>&1)"; code=$?
    if [[ "$code" == "$want_exit" && "$got" == *"$want"* ]]; then
        echo "  ✓ $what"
    else
        echo "  ✗ $what — exit $code, got:"; echo "$got" | sed 's/^/      /'; fail=1
    fi
}
expect "no input converts the default 2026"   0 "2026  →  MMXXVI"
expect "a numeral converts to a number"        0 "XIV  →  14"                     XIV
expect "out of range is rejected, exit 1"      1 "4000  ✗  4000 is out of range"  4000

just stop >/dev/null 2>&1
sleep 1
expect "server down is reported, exit 2"       2 "could not reach http://localhost:8000"
exit $fail
