#!/bin/bash
echo "=== Testing the running Wisp server ==="
cd "$(dirname "$0")/.."
trap 'just stop >/dev/null 2>&1' EXIT

just start || exit 1

fail=0
check() {  # <description> <expected substring> <curl args...>
    local what="$1" want="$2"; shift 2
    local got; got="$(curl -s --max-time 5 "$@")"
    if [[ "$got" == *"$want"* ]]; then echo "  ✓ $what"; else echo "  ✗ $what — got: $got"; fail=1; fi
}
check "GET /"              "Hello from Gleam!"                "http://localhost:8000/"
check "GET /greet/booth"   '{"greeting":"Hello, booth!"}'     "http://localhost:8000/greet/booth"
check "POST /reverse"      "maelg"                            -X POST --data "gleam" "http://localhost:8000/reverse"
check "GET /nope is 404"   "404"                              -o /dev/null -w "%{http_code}" "http://localhost:8000/nope"

just stop >/dev/null 2>&1
sleep 1
if curl -s --max-time 2 "http://localhost:8000/" >/dev/null; then
    echo "  ✗ server still answering after just stop"; fail=1
else
    echo "  ✓ just stop stops it"
fi
exit $fail
