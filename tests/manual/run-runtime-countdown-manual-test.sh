#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual Test: Runtime / Countdown / Exit Code
# Tests --show-run-time, --show-count-down, and --count-down-exit-code
# across all variants and multiple countdown durations.
#
# For each variant × duration, starts a booth with a countdown timer and
# verifies: timer display, warning dialogs, auto-shutdown, and exit code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTH_BIN="${PROJECT_ROOT}/codingbooth"
PLAYGROUND_DIR="${PROJECT_ROOT}/examples/workspaces/empty-example"

VARIANTS=()
DURATIONS=()
SKIP_BUILD=false
EXIT_CODE_TO_TEST=42
PASSED=0
FAILED=0

usage() {
    echo "Usage: $0 [--variant <name>]... [--duration <label>]... [--skip-build] [--exit-code <code>]"
    echo ""
    echo "  --variant <name>     Test specific variant(s). Can be repeated."
    echo "                       Default: base codeserver notebook desktop-xfce desktop-kde terminal"
    echo "  --duration <label>   Test specific duration(s). Can be repeated."
    echo "                       Options: 15min, 10min, 5min, 0min"
    echo "                       Default: all four"
    echo "  --exit-code <code>   Exit code to test with (default: 42)"
    echo "  --skip-build         Skip building CLI before testing"
    echo "  --help, -h           Show this help"
    echo ""
    echo "Durations:"
    echo "  15min   Starts with ~15min10s countdown (tests 15min warning)"
    echo "  10min   Starts with ~10min10s countdown (tests 10min warning, skips 15min)"
    echo "  5min    Starts with ~5min10s countdown  (tests 5min warning, skips 15/10min)"
    echo "  0min    Starts with ~15s countdown      (tests immediate expiry and exit code)"
    echo ""
    echo "What to verify for each run:"
    echo "  - Run time timer is shown (grey, counting up)"
    echo "  - Countdown timer is shown (green -> yellow -> orange -> red)"
    echo "  - Warning dialogs appear at correct thresholds"
    echo "  - Only relevant warnings appear (e.g. no 15min warning if started with 10min)"
    echo "  - Auto-shutdown triggers on expiry"
    echo "  - Exit code matches --count-down-exit-code value"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test all variants, all durations"
    echo "  $0 --variant base --duration 0min     # Quick test: base variant, immediate expiry"
    echo "  $0 --variant base --variant codeserver --duration 5min"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)
            [[ $# -lt 2 ]] && { echo "Error: --variant requires a value"; exit 2; }
            VARIANTS+=("$2")
            shift 2
            ;;
        --duration)
            [[ $# -lt 2 ]] && { echo "Error: --duration requires a value"; exit 2; }
            DURATIONS+=("$2")
            shift 2
            ;;
        --exit-code)
            [[ $# -lt 2 ]] && { echo "Error: --exit-code requires a value"; exit 2; }
            EXIT_CODE_TO_TEST="$2"
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
    VARIANTS=(base codeserver notebook desktop-xfce desktop-kde terminal)
fi

if [[ ${#DURATIONS[@]} -eq 0 ]]; then
    DURATIONS=(15min 10min 5min 0min)
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

duration_seconds() {
    case "$1" in
        15min) echo 910 ;;   # 15min + 10s
        10min) echo 610 ;;   # 10min + 10s
        5min)  echo 310 ;;   #  5min + 10s
        0min)  echo 15 ;;    # 15s
        *)     echo "Error: unknown duration: $1" >&2; exit 2 ;;
    esac
}

expected_warnings() {
    # Returns which warnings should appear for this duration
    case "$1" in
        15min) echo "15min(auto-dismiss 60s), 10min(OK required), 5min(OK required)" ;;
        10min) echo "10min(OK required), 5min(OK required)" ;;
        5min)  echo "5min(OK required)" ;;
        0min)  echo "none (immediate shutdown)" ;;
    esac
}

# ── Build CLI ──
if [[ "$SKIP_BUILD" != true ]]; then
    header "Building CLI"
    "${PROJECT_ROOT}/build/cli-build.sh" 2>&1 | tail -5
fi

# Pick a random port
TEST_PORT=$((30000 + RANDOM % 35000))

# ── Test matrix ──
for variant in "${VARIANTS[@]}"; do
    for duration in "${DURATIONS[@]}"; do
        subheader "$variant / $duration"

        NAME="rt-test-${variant}-${duration}-$$"
        PORT=$TEST_PORT
        COUNTDOWN_SEC=$(duration_seconds "$duration")
        NOW=$(date +%s)
        END_EPOCH=$((NOW + COUNTDOWN_SEC))
        WARNINGS=$(expected_warnings "$duration")

        echo ""
        echo "  Variant:          $variant"
        echo "  Duration:         $duration ($COUNTDOWN_SEC seconds)"
        echo "  Countdown epoch:  $END_EPOCH"
        echo "  Expected exit:    $EXIT_CODE_TO_TEST"
        echo "  Expected warnings: $WARNINGS"
        echo ""

        cd "$PLAYGROUND_DIR"

        # Build the command
        BOOTH_ARGS=(
            --variant "$variant"
            --name "$NAME"
            --port "$PORT"
            --show-run-time
            --show-count-down "$END_EPOCH"
            --count-down-exit-code "$EXIT_CODE_TO_TEST"
            --silence-build
        )

        if [[ "$variant" == "terminal" ]]; then
            # Terminal variant runs in foreground with -- bash
            # We need to run it in the background and capture exit code
            echo "  Starting booth (terminal mode, backgrounded)..."
            echo "  Command: $BOOTH_BIN ${BOOTH_ARGS[*]} -- bash -c 'sleep $((COUNTDOWN_SEC + 30))'"
            echo ""
            echo "  ┌─────────────────────────────────────────────────────┐"
            echo "  │  Terminal variant: timer shows in prompt.           │"
            echo "  │  Press ENTER in the booth terminal to see updates.  │"
            echo "  │  Booth will auto-shutdown when countdown expires.   │"
            echo "  └─────────────────────────────────────────────────────┘"
            echo ""

            "$BOOTH_BIN" "${BOOTH_ARGS[@]}" -- bash -c "sleep $((COUNTDOWN_SEC + 30))" &
            BOOTH_PID=$!

            # Wait for it to finish (auto-shutdown)
            echo "  Waiting for auto-shutdown (up to $((COUNTDOWN_SEC + 60))s)..."
            wait "$BOOTH_PID" 2>/dev/null
            actual_exit=$?
        else
            # Web variants run in foreground
            echo "  Starting booth (foreground, will auto-shutdown on expiry)..."
            echo "  Command: $BOOTH_BIN ${BOOTH_ARGS[*]}"

            # Determine URL
            case "$variant" in
                notebook)
                    BOOTH_URL="http://localhost:$PORT/booth"
                    ;;
                *)
                    BOOTH_URL="http://localhost:$PORT"
                    ;;
            esac

            echo ""
            echo "  ┌─────────────────────────────────────────────────────┐"
            echo "  │  Open this URL in your browser:                     │"
            echo "  │  $BOOTH_URL"
            echo "  │                                                     │"
            echo "  │  Verify:                                            │"
            echo "  │  - Run time timer (grey, counting up)               │"
            echo "  │  - Countdown timer (colored, counting down)         │"
            echo "  │  - Warning dialogs: $WARNINGS"
            echo "  │  - Auto-shutdown at 0                               │"
            echo "  └─────────────────────────────────────────────────────┘"
            echo ""

            "$BOOTH_BIN" "${BOOTH_ARGS[@]}" &
            BOOTH_PID=$!

            echo "  Waiting for auto-shutdown (up to $((COUNTDOWN_SEC + 60))s)..."
            wait "$BOOTH_PID" 2>/dev/null
            actual_exit=$?
        fi

        cd "$PROJECT_ROOT"

        echo ""
        echo "  ────────────────────────────────────"
        echo "  Expected exit code: $EXIT_CODE_TO_TEST"
        echo "  Actual exit code:   $actual_exit"

        if [[ "$actual_exit" -eq "$EXIT_CODE_TO_TEST" ]]; then
            echo "  ✅ PASSED (exit code matches)"
            PASSED=$((PASSED + 1))
        else
            echo "  ❌ FAILED (expected $EXIT_CODE_TO_TEST, got $actual_exit)"
            FAILED=$((FAILED + 1))
        fi

        # Cleanup in case container is still running
        docker rm -f "$NAME" 2>/dev/null || true

        echo ""
        echo "  Press ENTER to continue to next test..."
        read -r
    done
done

# ── Summary ──
header "Test Summary"
total=$((PASSED + FAILED))
echo ""
echo "  Variants tested:  ${VARIANTS[*]}"
echo "  Durations tested: ${DURATIONS[*]}"
echo "  Exit code tested: $EXIT_CODE_TO_TEST"
echo ""
echo "  ✅ Passed:  $PASSED"
echo "  ❌ Failed:  $FAILED"
echo "  Total:      $total"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo "  Result: SOME TESTS FAILED"
    exit 1
else
    echo "  Result: ALL TESTS PASSED"
    exit 0
fi
