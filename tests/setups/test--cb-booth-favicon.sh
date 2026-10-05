#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# cb-booth-favicon.sh picks the browser-tab icon: a project file under
# .booth/favicon/ (svg, then png, then ico), otherwise the built-in mark.
# Asserts on the link tag and the nginx locations it writes. No container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/variants/base/setups/cb-booth-favicon.sh"
BASE="$REPO_ROOT/variants/base"
MARK="$REPO_ROOT/docs/favicon.png"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -20
        ALL_PASSED=false
    fi
}

# run_pick <dir> <default> <out>  — stderr kept in $PICK_ERR
run_pick() {
    PICK_ERR="$WORK/err"
    CB_FAVICON_DIR="$1" CB_FAVICON_DEFAULT="$2" \
        bash "$HELPER" "$3" >"$WORK/stdout" 2>"$PICK_ERR" && PICK_EXIT=0 || PICK_EXIT=$?
}

tiny_png="$WORK/mark.png"
cp "$MARK" "$tiny_png"

# --- built-in mark when the project folder is absent ---
out="$WORK/out-default"
run_pick "$WORK/no-such-dir" "$tiny_png" "$out"
hash=$(sha256sum "$tiny_png" | awk '{print substr($1,1,12)}')
check "absent project folder exits 0" "$([[ $PICK_EXIT -eq 0 ]] && echo true || echo false)" "$(cat "$PICK_ERR")"
check "absent project folder uses the built-in png" \
    "$(grep -qF "type=\"image/png\" href=\"/booth-assets/favicon.png?v=${hash}\"" "$out/link" && echo true || echo false)" \
    "$(cat "$out/link")"
check "built-in png answers /favicon.ico with 204" \
    "$(grep -qF 'return 204' "$out/locations" && echo true || echo false)" "$(cat "$out/locations")"
check "built-in png bytes are copied through" \
    "$(cmp -s "$tiny_png" "$out/favicon.png" && echo true || echo false)"

# --- svg wins over png and ico ---
proj="$WORK/proj-all"
mkdir -p "$proj"
printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>' >"$proj/favicon.svg"
cp "$tiny_png" "$proj/favicon.png"
printf 'ICO' >"$proj/favicon.ico"
out="$WORK/out-svg"
run_pick "$proj" "$tiny_png" "$out"
check "svg wins over png and ico" \
    "$(grep -qF 'type="image/svg+xml"' "$out/link" && [[ ! -f "$out/favicon.png" && ! -f "$out/favicon.ico" ]] && echo true || echo false)" \
    "$(cat "$out/link")"
check "svg response carries a sandbox CSP" \
    "$(grep -qF "default-src 'none'" "$out/locations" && grep -qF 'sandbox' "$out/locations" && echo true || echo false)" \
    "$(cat "$out/locations")"

# --- png wins over ico ---
proj="$WORK/proj-png"
mkdir -p "$proj"
cp "$tiny_png" "$proj/favicon.png"
printf 'ICO' >"$proj/favicon.ico"
out="$WORK/out-png"
run_pick "$proj" "$tiny_png" "$out"
check "png wins over ico" \
    "$(grep -qF 'type="image/png"' "$out/link" && [[ -f "$out/favicon.png" && ! -f "$out/favicon.ico" ]] && echo true || echo false)" \
    "$(cat "$out/link")"

# --- ico is served at /favicon.ico itself ---
proj="$WORK/proj-ico"
mkdir -p "$proj"
printf 'ICOBYTES' >"$proj/favicon.ico"
out="$WORK/out-ico"
run_pick "$proj" "$tiny_png" "$out"
check "ico is served at /favicon.ico" \
    "$(grep -qF 'location = /favicon.ico' "$out/locations" \
        && grep -qF "alias ${out}/favicon.ico" "$out/locations" \
        && ! grep -qF 'return 204' "$out/locations" \
        && echo true || echo false)" \
    "$(cat "$out/locations")"
check "ico bytes are copied through" \
    "$([[ $(cat "$out/favicon.ico") == ICOBYTES ]] && echo true || echo false)"

# --- symlink, empty, and oversized files are skipped ---
proj="$WORK/proj-skip"
mkdir -p "$proj"
printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>' >"$proj/real.svg"
ln -s real.svg "$proj/favicon.svg"
: >"$proj/favicon.png"
dd if=/dev/zero of="$proj/favicon.ico" bs=1024 count=300 status=none
out="$WORK/out-skip"
run_pick "$proj" "$tiny_png" "$out"
check "symlink, empty file, and oversized file fall through to the built-in mark" \
    "$(grep -qF 'type="image/png"' "$out/link" && grep -qF 'skipping' "$PICK_ERR" && echo true || echo false)" \
    "$(cat "$PICK_ERR"; echo '---'; cat "$out/link")"

# --- nothing at all ---
out="$WORK/out-none"
run_pick "$WORK/no-such-dir" "$WORK/no-such.png" "$out"
check "no project file and no built-in mark leaves the link empty" \
    "$([[ $PICK_EXIT -eq 0 && ! -s "$out/link" && ! -s "$out/locations" ]] && echo true || echo false)" \
    "$(cat "$PICK_ERR")"

# --- the pages and both nginx fronts actually consume the helper ---
check "console page, login page, and wrapper page carry the link placeholder" \
    "$(grep -qF '${BOOTH_FAVICON_LINK}' "$BASE/web-ttyd-split/index.html" \
        && grep -qF '${BOOTH_FAVICON_LINK}' "$BASE/web-ttyd-split/login.html" \
        && grep -qF '${BOOTH_FAVICON_LINK}' "$BASE/setups/booth-message-wrapper--setup.sh" \
        && echo true || echo false)"
check "both nginx templates have a favicon-locations slot" \
    "$(grep -qF '${FAVICON_LOCATIONS}' "$BASE/web-ttyd-split/nginx.conf.template" \
        && grep -qF '${FAVICON_LOCATIONS}' "$BASE/setups/booth-message-wrapper--setup.sh" \
        && echo true || echo false)"
check "console and wrapper start paths call the helper and pass both values to envsubst" \
    "$(grep -qF 'cb-booth-favicon.sh' "$BASE/start-ttyd-split" \
        && grep -qF '${FAVICON_LOCATIONS}' "$BASE/start-ttyd-split" \
        && grep -qF '${BOOTH_FAVICON_LINK}' "$BASE/start-ttyd-split" \
        && grep -qF 'cb-booth-favicon.sh' "$BASE/setups/booth-message-wrapper--setup.sh" \
        && echo true || echo false)"
check "image build stages docs/favicon.png into the default path" \
    "$(grep -qF 'docs/favicon.png' "$REPO_ROOT/build/docker-build.sh" \
        && grep -qF '/usr/local/share/codingbooth/favicon.png' "$BASE/Dockerfile" \
        && echo true || echo false)"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
