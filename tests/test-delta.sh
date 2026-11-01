#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# test-delta.sh — run every test that covers what changed since f497872b
#
#   arm64 gaps (flutter, sqls, dbeaver, heidisql, elm 0.19.1, HLS), prebuilt
#   GnuPG / protoc-gen-prost / protoc-gen-tonic / GoNB, EnvFolio 1.1.0, and the
#   flutter/heidisql fixtures now running the built-in setups.
#
# Stages, cheapest first; a failure is recorded and the run goes on:
#
#   images    rebuild base, notebook, desktop-xfce from this tree (a no-op when
#             fresh): the changed setups only reach complex tests and examples
#             through the image
#   unit      Go unit tests, the setups suite, the config tests
#   basic     basic/test034 (EnvFolio 1.1.0 on the base image's GnuPG 2.5)
#   complex   elm, heidisql, flutter, lsp-hls-zls
#   examples  go (GoNB kernel), haskell (HLS, IHaskell), flutter, data (dbeaver)
#
# Usage:
#   tests/test-delta.sh                    all stages
#   tests/test-delta.sh unit complex       only these stages
#   tests/test-delta.sh --list             print what each stage runs
#
# Not covered by any test (check by hand if it matters): lsp+sql (sqls),
# protobuf+rust in a real booth, and arm64 — run this on an arm64 host for that.
# -----------------------------------------------------------------------------

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_STAGES=(images unit basic complex examples)

VARIANTS=(base notebook desktop-xfce)
CONFIG_TESTS=(
    init/test114-select-new-protoplugins-ant-cuda.sh
    catalog/test92-arch-unsupported-is-declared.sh
    init/test94-init-flutter.sh
    init/test140-init-lsp.sh
)
COMPLEX_TESTS=(
    boothfile/test-boothfile-elm/test--boothfile-elm.sh
    boothfile/test-boothfile-heidisql/test--boothfile-heidisql.sh
    boothfile/test-boothfile-flutter/test--boothfile-flutter.sh
    boothfile/test-boothfile-lsp-hls-zls/test--boothfile-lsp-hls-zls.sh
)
EXAMPLES=(go haskell flutter data)

if [[ "${1:-}" == "--list" ]]; then
    echo "images:   ensure_fresh_image ${VARIANTS[*]}"
    echo "unit:     (cd cli && go test ./src/pkg/boothfile/ ./src/pkg/booth/)"
    echo "          tests/setups/run-setups-tests.sh"
    printf '          tests/config/%s\n' "${CONFIG_TESTS[@]}"
    echo "basic:    tests/basic/test034--envfolio.sh"
    printf 'complex:  tests/complex/%s\n' "${COMPLEX_TESTS[@]}"
    echo "examples: examples/workspaces/run-example-tests.sh$(printf ' --example %s' "${EXAMPLES[@]}")"
    exit 0
fi

STAGES=("$@")
[[ ${#STAGES[@]} -eq 0 ]] && STAGES=("${ALL_STAGES[@]}")
for s in "${STAGES[@]}"; do
    [[ " ${ALL_STAGES[*]} " == *" $s "* ]] || { echo "Unknown stage '$s' (one of: ${ALL_STAGES[*]})" >&2; exit 2; }
done
want() { [[ " ${STAGES[*]} " == *" $1 "* ]]; }

docker info >/dev/null 2>&1 || { echo "Docker is not running." >&2; exit 1; }

PASSED=()
FAILED=()
# run <label> <dir> <command...>: one check, in its own folder, recorded either way.
run() {
    local label="$1" dir="$2"; shift 2
    echo
    echo "################ $label"
    if (cd "$dir" && "$@"); then
        PASSED+=("$label")
    else
        FAILED+=("$label")
    fi
}

# The booth binary every stage runs, and the example wrappers + shared cache.
run "cli build"            "$REPO" ./build/cli-build.sh
want examples && run "example wrappers" "$REPO" ./examples/update-booth.sh

if want images; then
    source "$REPO/tests/ensure-fresh-image--source.sh"
    run "images: ${VARIANTS[*]}" "$REPO" ensure_fresh_image "${VARIANTS[@]}"
fi

if want unit; then
    run "go test boothfile+booth" "$REPO/cli" go test ./src/pkg/boothfile/ ./src/pkg/booth/ -count=1
    run "setups suite"            "$REPO/tests/setups" ./run-setups-tests.sh
    for t in "${CONFIG_TESTS[@]}"; do
        run "config/$t" "$REPO/tests/config" bash "$t"
    done
fi

if want basic; then
    run "basic/test034--envfolio" "$REPO/tests/basic" bash test034--envfolio.sh
fi

if want complex; then
    for t in "${COMPLEX_TESTS[@]}"; do
        run "complex/${t%%/test--*}" "$REPO/tests/complex/$(dirname "$t")" bash "$(basename "$t")"
    done
fi

if want examples; then
    args=()
    for e in "${EXAMPLES[@]}"; do args+=(--example "$e"); done
    run "examples: ${EXAMPLES[*]}" "$REPO/examples/workspaces" ./run-example-tests.sh "${args[@]}"
fi

echo
echo "================ test-delta summary"
for p in ${PASSED[@]+"${PASSED[@]}"}; do echo "  ✅ $p"; done
for f in ${FAILED[@]+"${FAILED[@]}"}; do echo "  ❌ $f"; done
echo "  ${#PASSED[@]} passed, ${#FAILED[@]} failed"
[[ ${#FAILED[@]} -eq 0 ]]
