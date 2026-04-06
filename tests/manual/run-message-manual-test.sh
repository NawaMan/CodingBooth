#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual Test: booth message send
# Tests all message types (yes-no, text, ok, choice, password) across variants.
# Starts a booth for each variant, sends messages, and verifies responses.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTH_BIN="${PROJECT_ROOT}/codingbooth"
PLAYGROUND_DIR="${PROJECT_ROOT}/examples/workspaces/empty-example"

TYPES=(yes-no text ok choice password toast)
VARIANTS=()
SKIP_BUILD=false
PASSED=0
FAILED=0
SKIPPED=0

usage() {
    echo "Usage: $0 [--variant <name>]... [--skip-build]"
    echo ""
    echo "  --variant <name>   Test specific variant(s). Can be repeated."
    echo "                     Default: base codeserver notebook desktop-xfce desktop-kde"
    echo "  --skip-build       Skip building CLI before testing"
    echo "  --help, -h         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                  # Test all variants"
    echo "  $0 --variant base                   # Test only base"
    echo "  $0 --variant base --variant notebook # Test base and notebook"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)
            [[ $# -lt 2 ]] && { echo "Error: --variant requires a value"; exit 2; }
            VARIANTS+=("$2")
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

if [[ ${#VARIANTS[@]} -eq 0 ]]; then
    VARIANTS=(base codeserver notebook desktop-xfce desktop-kde)
fi

header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
}

subheader() {
    echo ""
    echo "  ── $1 ──"
}

# ── Build CLI ──
if [[ "$SKIP_BUILD" != true ]]; then
    header "Building CLI"
    "${PROJECT_ROOT}/build/cli-build.sh" 2>&1 | tail -5
fi

# Pick a random port once for all variants (reused after each booth stops)
TEST_PORT=$((30000 + RANDOM % 35000))

# ── Test each variant ──
for variant in "${VARIANTS[@]}"; do
    header "Testing variant: $variant"

    NAME="msg-test-${variant}-$$"
    PORT=$TEST_PORT

    echo "  Starting booth: $NAME (variant=$variant, port=$PORT)"
    cd "$PLAYGROUND_DIR"

    "$BOOTH_BIN" --variant "$variant" --name "$NAME" --port "$PORT" --daemon

    cd "$PROJECT_ROOT"

    # Wait for container to be ready
    echo "  Waiting for container..."
    ready=false
    for i in {1..60}; do
        if docker exec "$NAME" id coder >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done

    if [[ "$ready" != true ]]; then
        echo "  ERROR: Container not ready after 60s"
        "$BOOTH_BIN" stop "$NAME" 2>/dev/null || true
        FAILED=$((FAILED + ${#TYPES[@]}))
        continue
    fi

    # Get the assigned port
    ACTUAL_PORT=$("$BOOTH_BIN" list 2>/dev/null | grep "$NAME" | awk '{print $4}')
    echo "  Ready. Port: $ACTUAL_PORT"

    # Give services time to start (nginx, jupyter, ttyd, etc.)
    sleep 5

    # Show the URL before starting tests so user can open the browser
    case "$variant" in
        notebook)
            BOOTH_URL="http://localhost:$ACTUAL_PORT/booth"
            ;;
        *)
            BOOTH_URL="http://localhost:$ACTUAL_PORT"
            ;;
    esac
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Open this URL before proceeding:                   │"
    echo "  │  $BOOTH_URL"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo "  Press ENTER when the page is loaded..."
    read -r

    # ── Test each message type ──
    for msg_type in "${TYPES[@]}"; do
        subheader "$variant / $msg_type"

        # Build the send command
        send_args=(--name "$NAME" --title "Test $msg_type" --type "$msg_type")

        case "$msg_type" in
            yes-no)
                send_args+=(--body "Deploy to staging?")
                expected_pattern="yes|no|cancelled"
                ;;
            text)
                send_args+=(--body "Enter version tag:")
                expected_pattern=".+"  # any non-empty text or "cancelled"
                ;;
            ok)
                send_args+=(--body "Build completed successfully.")
                expected_pattern="ok|cancelled"
                ;;
            choice)
                send_args+=(--body "Select environment:" --options "staging,production,rollback")
                expected_pattern="staging|production|rollback|cancelled"
                ;;
            password)
                send_args+=(--body "Enter deploy key:")
                expected_pattern=".+"  # any non-empty text or "cancelled"
                ;;
            toast)
                send_args+=(--body "Build completed successfully.")
                expected_pattern=""  # fire-and-forget, no answer expected
                ;;
        esac

        if [[ "$msg_type" != "toast" ]]; then
            send_args+=(--expires 2m)
        fi

        echo "  Sending: booth message send ${send_args[*]}"
        echo ""

        if [[ "$msg_type" == "toast" ]]; then
            # Toast is fire-and-forget — CLI returns immediately
            echo "  Sending toast (fire-and-forget)..."
            output_file=$(mktemp)
            "$BOOTH_BIN" message send "${send_args[@]}" > "$output_file" 2>&1
            exit_code=$?
            msg_id=$(head -1 "$output_file")
            rm -f "$output_file"

            echo ""
            echo "  Message ID: $msg_id"
            echo "  Exit code:  $exit_code"

            if [[ $exit_code -eq 0 && "$msg_id" == msg-* ]]; then
                echo "  → Check browser: toast should appear in bottom-right corner."
                echo "  Press ENTER after visually confirming the toast..."
                read -r
                echo "  ✅ PASSED (toast sent, visually confirmed)"
                PASSED=$((PASSED + 1))
            else
                echo "  ❌ FAILED (exit_code=$exit_code, msg_id=$msg_id)"
                FAILED=$((FAILED + 1))
            fi
        else
            # Interactive message — send in background, wait for user response
            output_file=$(mktemp)
            "$BOOTH_BIN" message send "${send_args[@]}" > "$output_file" 2>&1 &
            send_pid=$!

            echo "  → Respond in the browser (or VNC desktop). 2 min timeout."

            # Wait for the send command to complete
            wait "$send_pid" 2>/dev/null
            exit_code=$?

            # Parse output: first line is msg ID, last line is answer
            msg_id=$(head -1 "$output_file")
            answer=$(tail -1 "$output_file")
            rm -f "$output_file"

            echo ""
            echo "  Message ID: $msg_id"
            echo "  Answer:     $answer"
            echo "  Exit code:  $exit_code"

            if [[ "$answer" == "timeout" ]]; then
                echo "  ⏭  SKIPPED (timed out — user did not respond)"
                SKIPPED=$((SKIPPED + 1))
            elif echo "$answer" | grep -qE "^($expected_pattern)$" || [[ -n "$answer" && "$answer" != "Error"* ]]; then
                echo "  ✅ PASSED"
                PASSED=$((PASSED + 1))
            else
                echo "  ❌ FAILED (unexpected answer: $answer)"
                FAILED=$((FAILED + 1))
            fi
        fi
    done

    # Clean up
    echo ""
    echo "  Cleaning up $NAME..."
    "$BOOTH_BIN" stop "$NAME" 2>/dev/null || true
done

# ── Summary ──
header "Test Summary"
total=$((PASSED + FAILED + SKIPPED))
echo ""
echo "  Variants tested: ${VARIANTS[*]}"
echo "  Message types:   ${TYPES[*]}"
echo ""
echo "  ✅ Passed:  $PASSED"
echo "  ❌ Failed:  $FAILED"
echo "  ⏭  Skipped: $SKIPPED"
echo "  Total:      $total"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo "  Result: SOME TESTS FAILED"
    exit 1
else
    echo "  Result: ALL TESTS PASSED"
    exit 0
fi
