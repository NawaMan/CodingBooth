#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# test-delta.sh — run every test that covers what changed since 42b28a7a
#
#   empty-example back to empty (config.toml only), wails-example's suite run in
#   a booth that has its desktop, wails+android building with one --platform
#   (extension 0.1.1 and the CLI's buildPlatformFlag), and the Android build
#   outputs the wails examples now gitignore.
#
# Stages, cheapest first; a failure is recorded and the run goes on:
#
#   unit      Go unit tests of the booth package (buildPlatformFlag), the
#             catalog version check (android--extension.toml was bumped), the
#             wails config test, and a dry run of each --platform example:
#             `docker build` gets the flag exactly once, also from the
#             wails-android config.toml as generated before the fix
#   examples  empty, wails (test004: the GUI on the booth's desktop),
#             wails-android (APK + emulator boot, when /dev/kvm is usable) and
#             android (the other example that sets --platform, in common-args),
#             then: none of them left untracked or changed files behind
#
# Usage:
#   tests/test-delta.sh                    all stages
#   tests/test-delta.sh unit               only these stages
#   tests/test-delta.sh --list             print what each stage runs
#   tests/test-delta.sh --no-build unit    skip the CLI build (./codingbooth is fresh)
#
# Every check writes its own log, and a check that calls booth also a trace of
# each booth call with its stderr (CB_DIAG_LOG). All of it lands in
# tests/logs/test-delta/<timestamp>/, with REPORT.txt: one line per check, then
# the failure lines and the tail of each failed check's log — plain text, made
# to be pasted whole into a review.
#
# Not covered: arm64, where wails-android and android are unsupported (Google's
# SDK is x86_64 only) and CB_ANDROID_PLATFORM decides what happens.
# -----------------------------------------------------------------------------

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_STAGES=(unit examples)

CONFIG_TESTS=(
    init/test100-init-wails.sh
)
# Examples whose config.toml sets --platform: the build must get it once.
PLATFORM_EXAMPLES=(wails-android-example android-example)
# The fix's own baseline: wails-android's config.toml from before it, which put
# --platform in build-args as well as run-args.
PLATFORM_BEFORE=42b28a7a
EXAMPLES=(empty wails wails-android android)

if [[ "${1:-}" == "--list" ]]; then
    echo "unit:     (cd cli && go test ./src/pkg/booth/)"
    echo "          build/check-catalog-versions.sh"
    printf '          tests/config/%s\n' "${CONFIG_TESTS[@]}"
    printf '          codingbooth --dryrun --code examples/workspaces/%s: one --platform in docker build\n' "${PLATFORM_EXAMPLES[@]}"
    echo "          the same for wails-android-example with its ${PLATFORM_BEFORE} config.toml"
    printf 'examples: examples/workspaces/run-example-tests.sh --example %s\n' "${EXAMPLES[@]}"
    echo "          git status of those examples is clean"
    exit 0
fi

BUILD=true
if [[ "${1:-}" == "--no-build" ]]; then BUILD=false; shift; fi

STAGES=("$@")
[[ ${#STAGES[@]} -eq 0 ]] && STAGES=("${ALL_STAGES[@]}")
for s in "${STAGES[@]}"; do
    [[ " ${ALL_STAGES[*]} " == *" $s "* ]] || { echo "Unknown stage '$s' (one of: ${ALL_STAGES[*]})" >&2; exit 2; }
done
want() { [[ " ${STAGES[*]} " == *" $1 "* ]]; }

docker info >/dev/null 2>&1 || { echo "Docker is not running." >&2; exit 1; }

RUN_DIR="$REPO/tests/logs/test-delta/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
RUN_START=$(date +%s)

RESULTS=()   # "<PASS|FAIL> <seconds> <log> <label>", in run order
N=0

# run <label> <dir> <command...>: one check, in its own folder, recorded either
# way. Output goes to the terminal and to its own log, with a booth-call trace
# (CB_DIAG_LOG) beside it.
run() {
    local label="$1" dir="$2"; shift 2
    N=$((N + 1))
    local slug log start rc
    slug=$(printf '%02d-%s' "$N" "$(echo "$label" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//')")
    log="$RUN_DIR/$slug.log"
    echo
    echo "################ $label    (log: ${log#$REPO/})"
    start=$(date +%s)
    # stdin is /dev/null: a check that reads stdin must not eat the terminal's.
    (cd "$dir" && CB_DIAG_LOG="$RUN_DIR/$slug.booth-calls.log" "$@") < /dev/null 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    local status=PASS
    [[ $rc -eq 0 ]] || status=FAIL
    RESULTS+=("$status $(( $(date +%s) - start )) $log $label")
}

# one_build_platform <code dir>: the `docker build` a dry run prints carries
# --platform exactly once. Twice is what buildx reads as a multi-platform
# build, and the default docker driver refuses it.
one_build_platform() {
    local out n
    out="$("$REPO/codingbooth" --dryrun --port 50999 --code "$1" -- true 2>&1)" || { echo "$out"; return 1; }
    sed -n '/^ *build \\$/,/^ *-f /p' <<< "$out"
    n=$(sed -n '/^ *build \\$/,/^ *-f /p' <<< "$out" | grep -c -- '--platform')
    echo "docker build gets --platform $n time(s), want 1"
    [[ $n -eq 1 ]]
}

# one_build_platform_before: the same, for wails-android-example's .booth/ with
# the config.toml it had before the fix (build-args and run-args both).
one_build_platform_before() {
    local ws="$RUN_DIR/wails-android-before"
    rm -rf "$ws" && mkdir -p "$ws"
    cp -r "$REPO/examples/workspaces/wails-android-example/.booth" "$ws/"
    git -C "$REPO" show "$PLATFORM_BEFORE:examples/workspaces/wails-android-example/.booth/config.toml" \
        > "$ws/.booth/config.toml" || return 1
    grep -q '^build-args = \["--platform"' "$ws/.booth/config.toml" \
        || { echo "the $PLATFORM_BEFORE config.toml has no build-args --platform; nothing to prove"; return 1; }
    one_build_platform "$ws"
}

# tree_clean <path...>: nothing changed or untracked under these paths. Run
# after the examples, it catches build outputs that are not gitignored (and,
# on a dirty tree, your own edits there too).
tree_clean() {
    local dirty
    dirty="$(git -C "$REPO" status --porcelain -- "$@")"
    [[ -z "$dirty" ]] && { echo "clean"; return 0; }
    echo "$dirty"
    return 1
}

# The booth binary every stage runs, and the example wrappers + shared cache.
$BUILD && run "cli build" "$REPO" ./build/cli-build.sh
want examples && run "example wrappers" "$REPO" ./examples/update-booth.sh

if want unit; then
    run "go test booth"           "$REPO/cli" go test ./src/pkg/booth/ -count=1
    run "catalog versions"        "$REPO" ./build/check-catalog-versions.sh
    for t in "${CONFIG_TESTS[@]}"; do
        run "config/${t%.sh}" "$REPO/tests/config" bash "$t"
    done
    for e in "${PLATFORM_EXAMPLES[@]}"; do
        run "dryrun/$e: one build --platform" "$REPO" one_build_platform "$REPO/examples/workspaces/$e"
    done
    run "dryrun/wails-android-example ($PLATFORM_BEFORE config): one build --platform" "$REPO" one_build_platform_before
fi

if want examples; then
    # One example per check, so each gets its own line and log. The runner also
    # keeps its own per-example log, examples/workspaces/.<name>.log.
    for e in "${EXAMPLES[@]}"; do
        run "example/$e" "$REPO/examples/workspaces" ./run-example-tests.sh --example "$e"
    done
    paths=()
    for e in "${EXAMPLES[@]}"; do paths+=("examples/workspaces/$e-example"); done
    run "examples left the tree clean" "$REPO" tree_clean "${paths[@]}"
fi

# ---------------- Report ----------------
fmt_secs() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

REPORT="$RUN_DIR/REPORT.txt"
{
    passed=0; failed=0
    for r in "${RESULTS[@]}"; do [[ $r == PASS* ]] && passed=$((passed + 1)) || failed=$((failed + 1)); done

    echo "test-delta report"
    echo "  commit:   $(git -C "$REPO" rev-parse --short HEAD) on $(git -C "$REPO" branch --show-current)$( [[ -n "$(git -C "$REPO" status --porcelain)" ]] && echo ' (uncommitted changes)')"
    echo "  host:     $(uname -sm), $(docker version --format 'docker {{.Server.Version}}' 2>/dev/null)"
    echo "  stages:   ${STAGES[*]}"
    echo "  started:  $(date -d "@$RUN_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$RUN_START" '+%Y-%m-%d %H:%M:%S')"
    echo "  duration: $(fmt_secs $(( $(date +%s) - RUN_START )))"
    echo "  result:   $passed passed, $failed failed"
    echo "  logs:     ${RUN_DIR#$REPO/}/"
    echo
    echo "Checks"
    for r in "${RESULTS[@]}"; do
        read -r status secs log label <<< "$r"
        printf '  %-4s %8s  %s\n' "$status" "$(fmt_secs "$secs")" "$label"
    done

    if (( failed > 0 )); then
        for r in "${RESULTS[@]}"; do
            read -r status secs log label <<< "$r"
            [[ $status == FAIL ]] || continue
            echo
            echo "=============================================================================="
            echo "FAIL  $label"
            if [[ ! -f "$log" ]]; then
                echo "  (no log)"
                continue
            fi
            echo "  log: ${log#$REPO/}"
            calls="${log%.log}.booth-calls.log"
            [[ -s "$calls" ]] && echo "  booth calls: ${calls#$REPO/}"
            echo "--- failure lines"
            grep -E '❌|FAILED|FAIL:|Error|ERROR|error:' "$log" | grep -v '^#[0-9]' | head -30 | sed 's/^/  /'
            echo "--- last 40 lines"
            tail -40 "$log" | sed 's/^/  /'
            if [[ -s "$calls" ]]; then
                echo "--- booth calls that exited non-zero (command, stderr)"
                awk '/ === codingbooth /{cmd=$0; buf=""; next}
                     / --- rc=/{ if ($0 !~ /rc=0$/) { print cmd; printf "%s", buf; print } ; buf=""; next }
                     { buf = buf $0 "\n" }' "$calls" | tail -40 | sed 's/^/  /'
            fi
        done
    fi
} > "$REPORT"

# Strip colour codes from the report so it pastes cleanly.
sed -i 's/\x1b\[[0-9;]*m//g' "$REPORT" 2>/dev/null || true

echo
echo "================ test-delta report (${REPORT#$REPO/})"
cat "$REPORT"
grep -q '^  result:   [0-9]* passed, 0 failed$' "$REPORT"
