#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the Deno, Lua and Scala notebook kernels inside a real notebook image
#
# The deno+kernel, lua+kernel and scala+kernel extensions emit these setups. Each
# language and its kernel are set up in a throwaway container of the notebook
# image — the repo's kernel setups are mounted in, so the image does not have to
# carry the current scripts — and the result is committed to a scratch image.
# A second container, as the booth user and with no network, then runs a cell in
# every kernel through jupyter_client and asserts on what each one prints.
#
# Running a cell is the point: a kernel can register, appear in
# `jupyter kernelspec list`, and still fail every cell. Scala did — a kernelspec
# written where Jupyter does not look, a standalone launcher the Scala 3 compiler
# cannot read its classpath from, and one that re-resolved its jars over the
# network at every start. So did Lua — the `ilua` console started in place of the
# kernel, ILua dying on a home with no Jupyter runtime dir yet, and the wheel's
# own kernelspec shadowing the fixed one.
#
# SCALA_VERSION is set to a release Almond has no kernel for, as the scala
# template's Boothfile arg does, to prove the kernel picks its own Scala.
#
# Image: CB_NOTEBOOK_IMAGE (default: the notebook image of this checkout's
# version.txt).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
VERSION="$(tr -d ' \t\n\r' < "$REPO_ROOT/version.txt")"
NB_IMAGE="${CB_NOTEBOOK_IMAGE:-nawaman/codingbooth:notebook-${VERSION}}"
SCRATCH_IMAGE="cb-test-notebook-kernels:$$"
SCRATCH_CONTAINER="cb-test-notebook-kernels-$$"

echo "=== Test: Deno, Lua and Scala notebook kernels run a cell ==="

cleanup() {
    docker rm -f "$SCRATCH_CONTAINER" >/dev/null 2>&1 || true
    docker rmi -f "$SCRATCH_IMAGE"    >/dev/null 2>&1 || true
}
trap cleanup EXIT

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

# has <output> <line> — the output contains exactly that line.
has() { grep -qxF -- "$2" <<< "$1"; }

MOUNTS=()
for s in deno-nb-kernel lua-nb-kernel scala-nb-kernel; do
    MOUNTS+=(-v "$SETUPS/$s--setup.sh:/opt/codingbooth/setups/$s--setup.sh:ro")
done

docker image inspect "$NB_IMAGE" >/dev/null 2>&1 || docker pull -q "$NB_IMAGE" >/dev/null

# ---- set up the languages and their kernels, as a Boothfile build would ----
INSTALL_OUT=$(docker run --name "$SCRATCH_CONTAINER" "${MOUNTS[@]}" -e SCALA_VERSION=3.9.0 \
    --entrypoint bash "$NB_IMAGE" -lc '
        set -e
        deno--setup.sh latest
        jdk--setup.sh 25 temurin
        lua--setup.sh --lua-version 5.4
        scala--setup.sh --scala-version "$SCALA_VERSION"
        for k in deno lua scala; do
            bash -lc "$k-nb-kernel--setup.sh" && echo "installed=$k"
        done
    ' < /dev/null 2>&1) || true
for k in deno lua scala; do
    has "$INSTALL_OUT" "installed=$k" \
        && check "true" "$k-nb-kernel--setup.sh installs on the notebook image" \
        || check "false" "$k-nb-kernel--setup.sh installs on the notebook image" "$(tail -20 <<< "$INSTALL_OUT")"
done
docker commit "$SCRATCH_CONTAINER" "$SCRATCH_IMAGE" >/dev/null

# ---- run a cell in each kernel: booth user, no network ----
CELL_OUT=$(docker run --rm --network none -u coder -e HOME=/home/coder \
    --entrypoint bash "$SCRATCH_IMAGE" -lc 'cd /tmp && python - <<'"'"'PY'"'"'
from jupyter_client.manager import start_new_kernel
cells = {
    "deno":  "console.log(\"deno-ok-\" + (6*7))",
    "lua":   "print(\"lua-ok-\" .. 6*7)",
    "scala": "println(\"scala-ok-\" + (6*7))",
}
for name, code in cells.items():
    out = []
    try:
        km, kc = start_new_kernel(kernel_name=name, startup_timeout=180)
        try:
            kc.execute_interactive(code, timeout=180, output_hook=lambda m: out.append(m["content"].get("text", "")) if m["msg_type"] == "stream" else None)
        finally:
            km.shutdown_kernel(now=True)
    except Exception as e:
        out.append(f"error: {e}")
    print(f"{name}=" + "".join(out).strip())
PY' < /dev/null 2>&1) || true
for k in deno lua scala; do
    has "$CELL_OUT" "$k=$k-ok-42" \
        && check "true" "The $k kernel runs a cell (booth user, no network)" \
        || check "false" "The $k kernel runs a cell (booth user, no network)" "$(grep -E "^$k=|Error|error" <<< "$CELL_OUT" | head -5)"
done

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ All $NUM checks passed"
else
    echo "❌ $FAILED of $NUM checks failed"
    exit 1
fi
