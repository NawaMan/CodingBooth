#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: protoc-gen-prost--setup.sh and protoc-gen-tonic--setup.sh
#
# Each installs its plugin from a CodingBoothPrebuilt release asset and only
# compiles it (cargo--install.sh --locked) when there is none. For both scripts:
#
#   1. A published asset is installed to /usr/local/bin, and cargo never runs.
#   2. No asset for the version: cargo installs exactly that version, --locked.
#   3. A version that is not X.Y.Z is rejected with exit 2.
#
# Hermetic: CB_PREBUILT_URL points at a fake release tree read as file://, and
# `install`, `sudo` and `cargo` are stubs that echo what they were asked to do, so
# nothing is written to /usr/local and nothing is built.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"

# The asset name comes from /etc/os-release, and the fixture and the lib both check
# assets with sha256sum: only the Linux the image runs on has all of that.
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum on this host"; exit 0; }
[ -r /etc/os-release ] || { echo "SKIP: no /etc/os-release on this host ($(uname -s))"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/stub"
cat > "$TMP/stub/install" <<'EOF'
#!/bin/bash
echo "STUB_INSTALL $*"
EOF
cat > "$TMP/stub/sudo" <<'EOF'
#!/bin/bash
echo "STUB_SUDO $*"
EOF
printf '#!/bin/bash\nexit 0\n' > "$TMP/stub/cargo"
chmod +x "$TMP/stub/install" "$TMP/stub/sudo" "$TMP/stub/cargo"

# shellcheck source=/dev/null
source "$SETUPS/libs/prebuilt-source.sh"

# A fake release of <tool> 0.5.0 for this machine; no other version is published.
make_release() {  # make_release <tool>
    local tool="$1" name
    name="$(cb_prebuilt_asset "$tool" 0.5.0 native)"
    mkdir -p "$TMP/stage/$name/bin" "$TMP/release/$tool-0.5.0"
    printf '#!/bin/sh\necho %s\n' "$tool" > "$TMP/stage/$name/bin/$tool"
    tar -czf "$TMP/release/$tool-0.5.0/$name.tar.gz" -C "$TMP/stage" "$name"
    (cd "$TMP/release/$tool-0.5.0" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
}

run_setup() {  # run_setup <tool> [args...]
    local tool="$1"; shift
    PATH="$TMP/stub:$PATH" CARGO_BIN="$TMP/stub/cargo" CB_PREBUILT_URL="file://$TMP/release" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$SETUPS/$tool--setup.sh" "$@" 2>&1
}

ALL_PASSED=true
TEST_NUM=0
report() {  # report <ok> <desc> [detail-lines...]
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        for line in "$@"; do echo "      $line"; done
        ALL_PASSED=false
    fi
}

for tool in protoc-gen-prost protoc-gen-tonic; do
    make_release "$tool"

    out="$(run_setup "$tool")" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ] \
       && echo "$out" | grep -qE "^STUB_INSTALL -m 755 .*/prebuilt/bin/$tool /usr/local/bin/$tool\$" \
       && ! echo "$out" | grep -q "cargo install"; then
        report true "$tool: the prebuilt 0.5.0 asset is installed to /usr/local/bin, no cargo"
    else
        report false "$tool: the prebuilt 0.5.0 asset is installed to /usr/local/bin, no cargo" "rc=$rc" "$out"
    fi

    out="$(run_setup "$tool" 0.4.1)" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ] \
       && echo "$out" | grep -qF "cargo install '$tool' --version '0.4.1' --locked" \
       && ! echo "$out" | grep -q "STUB_INSTALL"; then
        report true "$tool: a version not prebuilt is built by cargo, pinned and --locked"
    else
        report false "$tool: a version not prebuilt is built by cargo, pinned and --locked" "rc=$rc" "$out"
    fi

    out="$(run_setup "$tool" 0.5)" && rc=0 || rc=$?
    if [ "$rc" -eq 2 ] && echo "$out" | grep -qF "Not a $tool version: '0.5'"; then
        report true "$tool: a version that is not X.Y.Z is rejected"
    else
        report false "$tool: a version that is not X.Y.Z is rejected" "rc=$rc" "$out"
    fi
done

[ "$ALL_PASSED" = true ]
