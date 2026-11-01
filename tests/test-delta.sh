#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# test-delta.sh — run every test that covers what changed since f497872b
#
#   arm64 gaps (flutter, sqls, dbeaver, heidisql, elm 0.19.1, HLS), prebuilt
#   GnuPG / protoc-gen-prost / protoc-gen-tonic / GoNB, EnvFolio 1.1.0, the
#   complex fixtures and turtle-example now running the built-in setups, and
#   the examples that had tests but no runner (so never ran) now having one.
#
# Stages, cheapest first; a failure is recorded and the run goes on:
#
#   images    rebuild base, notebook, desktop-xfce from this tree (a no-op when
#             fresh): the changed setups only reach complex tests and examples
#             through the image
#   unit      the setup-shadowing guard, Go unit tests, the setups suite, the
#             config tests
#   basic     basic/test034 (EnvFolio 1.1.0 on the base image's GnuPG 2.5)
#   complex   elm, heidisql, flutter, lsp-hls-zls
#   cleanup   the setup-shadowing guard, then the 53 complex tests whose
#             .booth/setups/ copies of built-ins were deleted: they now run the
#             image's setups (also refreshes the desktop-kde, desktop-lxqt,
#             desktop-wayland, codeserver images)
#   examples  go (GoNB kernel), haskell (HLS, IHaskell), flutter, data (dbeaver),
#             turtle (Logo from the built-in files), and the examples whose
#             runner is new: empty, herdr, jetbrain-exmple, playground3,
#             playwright-polyglot, tiling, wails, wails-android
#
# Usage:
#   tests/test-delta.sh                    all stages
#   tests/test-delta.sh unit complex       only these stages
#   tests/test-delta.sh --list             print what each stage runs
#   tests/test-delta.sh --no-build unit    skip the CLI build (./codingbooth is fresh)
#
# Every check writes its own log, and complex checks also a trace of each booth
# call with its stderr (CB_DIAG_LOG). All of it lands in
# tests/logs/test-delta/<timestamp>/, with REPORT.txt: one line per check, then
# the failure lines and the tail of each failed check's log — plain text, made
# to be pasted whole into a review.
#
# Not covered by any test (check by hand if it matters): lsp+sql (sqls),
# protobuf+rust in a real booth, and arm64 — run this on an arm64 host for that.
# -----------------------------------------------------------------------------

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_STAGES=(images unit basic complex cleanup examples)

VARIANTS=(base notebook desktop-xfce)
CLEANUP_VARIANTS=(base desktop-xfce desktop-kde desktop-lxqt desktop-wayland codeserver)
CONFIG_TESTS=(
    init/test114-select-new-protoplugins-ant-cuda.sh
    catalog/test92-arch-unsupported-is-declared.sh
    init/test94-init-flutter.sh
    init/test140-init-lsp.sh
)
COMPLEX_TESTS=(
    boothfile/test-boothfile-elm
    boothfile/test-boothfile-heidisql
    boothfile/test-boothfile-flutter
    boothfile/test-boothfile-lsp-hls-zls
)
CLEANUP_TESTS=(
    boothfile/test-boothfile-aider
    boothfile/test-boothfile-alacritty
    boothfile/test-boothfile-ansible
    boothfile/test-boothfile-aws-cdk
    boothfile/test-boothfile-aws-sam-cli
    boothfile/test-boothfile-azure-cli
    boothfile/test-boothfile-binary-companions
    boothfile/test-boothfile-cmake
    boothfile/test-boothfile-codeserver-terminal-font
    boothfile/test-boothfile-cypress
    boothfile/test-boothfile-dblab
    boothfile/test-boothfile-default-terminal-kde
    boothfile/test-boothfile-default-terminal-lxqt
    boothfile/test-boothfile-default-terminal-wayland
    boothfile/test-boothfile-default-terminal-xfce
    boothfile/test-boothfile-dotnet
    boothfile/test-boothfile-floci
    boothfile/test-boothfile-gh-copilot
    boothfile/test-boothfile-ghostty
    boothfile/test-boothfile-gleam
    boothfile/test-boothfile-gradle
    boothfile/test-boothfile-harlequin
    boothfile/test-boothfile-helix
    boothfile/test-boothfile-helm
    boothfile/test-boothfile-jenv
    boothfile/test-boothfile-kde-terminal-font
    boothfile/test-boothfile-kitty
    boothfile/test-boothfile-kubectl
    boothfile/test-boothfile-latex
    boothfile/test-boothfile-lazydocker
    boothfile/test-boothfile-lazygit
    boothfile/test-boothfile-lazysql
    boothfile/test-boothfile-lxqt-terminal-font
    boothfile/test-boothfile-mojo
    boothfile/test-boothfile-mojo-nb-kernel
    boothfile/test-boothfile-mongodb
    boothfile/test-boothfile-n8n
    boothfile/test-boothfile-ollama
    boothfile/test-boothfile-posting
    boothfile/test-boothfile-pulumi
    boothfile/test-boothfile-puppeteer
    boothfile/test-boothfile-redis
    boothfile/test-boothfile-sbt
    boothfile/test-boothfile-selenium
    boothfile/test-boothfile-sql-studio
    boothfile/test-boothfile-sqluv
    boothfile/test-boothfile-terraform
    boothfile/test-boothfile-texstudio
    boothfile/test-boothfile-vscode-terminal-font
    boothfile/test-boothfile-wayland-terminal-font
    boothfile/test-boothfile-xfce-terminal-font
    boothfile/test-boothfile-xonsh
    boothfile/test-install-dotnet
)
EXAMPLES=(
    go haskell flutter data turtle
    # first automated run: they had tests but no run-automatic-on-host-test.sh
    empty herdr jetbrain-exmple playground3 playwright-polyglot tiling wails wails-android
)

if [[ "${1:-}" == "--list" ]]; then
    echo "images:   ensure_fresh_image ${VARIANTS[*]}"
    echo "unit:     build/check-setup-shadowing.sh"
    echo "          (cd cli && go test ./src/pkg/boothfile/ ./src/pkg/booth/)"
    echo "          tests/setups/run-setups-tests.sh"
    printf '          tests/config/%s\n' "${CONFIG_TESTS[@]}"
    echo "basic:    tests/basic/test034--envfolio.sh"
    printf 'complex:  tests/complex/%s\n' "${COMPLEX_TESTS[@]}"
    echo "cleanup:  build/check-setup-shadowing.sh"
    echo "          ensure_fresh_image ${CLEANUP_VARIANTS[*]}"
    printf '          tests/complex/%s\n' "${CLEANUP_TESTS[@]}"
    printf 'examples: examples/workspaces/run-example-tests.sh --example %s\n' "${EXAMPLES[@]}"
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
# way. Output goes to the terminal and to its own log; a complex check also gets
# a booth-call trace (CB_DIAG_LOG) beside it.
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

# run_complex <stage> <dir under tests/complex>
run_complex() {
    local stage="$1" d="$2" t
    t=$(cd "$REPO/tests/complex/$d" && ls test--*.sh 2>/dev/null | head -1)
    if [[ -z "$t" ]]; then
        N=$((N + 1))
        RESULTS+=("FAIL 0 - $stage/${d#*/} (no test--*.sh in tests/complex/$d)")
        return
    fi
    run "$stage/${d#*/}" "$REPO/tests/complex/$d" bash "$t"
}

# The booth binary every stage runs, and the example wrappers + shared cache.
$BUILD && run "cli build" "$REPO" ./build/cli-build.sh
want examples && run "example wrappers" "$REPO" ./examples/update-booth.sh

if want images || want cleanup; then
    source "$REPO/tests/ensure-fresh-image--source.sh"
fi
# The complex tests that call use_local_base_image build on
# cb-local/codingbooth:base-<version>, which ensure_fresh_image does not touch.
# Left stale, they test the old image's setups (flutter's arm64 skip, puppeteer,
# selenium). Point it at the base just checked, as build/build-all.sh does.
tag_cb_local_base() {
    local version
    version="$(tr -d ' \t\n\r' < "$REPO/version.txt")"
    run "tag cb-local base" "$REPO" \
        docker tag "nawaman/codingbooth:base-${version}" "cb-local/codingbooth:base-${version}"
}

if want images; then
    run "images: ${VARIANTS[*]}" "$REPO" ensure_fresh_image "${VARIANTS[@]}"
    tag_cb_local_base
fi

if want unit; then
    run "setup-shadowing guard"   "$REPO" ./build/check-setup-shadowing.sh
    run "go test boothfile+booth" "$REPO/cli" go test ./src/pkg/boothfile/ ./src/pkg/booth/ -count=1
    run "setups suite"            "$REPO/tests/setups" ./run-setups-tests.sh
    for t in "${CONFIG_TESTS[@]}"; do
        run "config/${t%.sh}" "$REPO/tests/config" bash "$t"
    done
fi

if want basic; then
    run "basic/test034--envfolio" "$REPO/tests/basic" bash test034--envfolio.sh
fi

if want complex; then
    for d in "${COMPLEX_TESTS[@]}"; do run_complex complex "$d"; done
fi

if want cleanup; then
    want unit || run "setup-shadowing guard" "$REPO" ./build/check-setup-shadowing.sh
    run "images: ${CLEANUP_VARIANTS[*]}" "$REPO" ensure_fresh_image "${CLEANUP_VARIANTS[@]}"
    want images || tag_cb_local_base
    for d in "${CLEANUP_TESTS[@]}"; do run_complex cleanup "$d"; done
fi

if want examples; then
    # One example per check, so each gets its own line and log. The runner also
    # keeps its own per-example log, examples/workspaces/.<name>.log.
    for e in "${EXAMPLES[@]}"; do
        run "example/$e" "$REPO/examples/workspaces" ./run-example-tests.sh --example "$e"
    done
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
