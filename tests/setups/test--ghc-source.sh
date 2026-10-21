#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: libs/ghc-source.sh — GHC into a ghcup tree, prebuilt when possible
#
# The haskell and haskell-nb-kernel setups call cb_ghc_install instead of
# `ghcup install ghc`. The cases that matter:
#
#   1. A tag (recommended) resolves through ghcup's list to a version with a
#      prebuilt: it unpacks into .ghcup/ghc/<version>, the wrapper scripts name the
#      new prefix, the versioned links `ghcup install` would add are there, and
#      ghcup itself installs nothing.
#   2. A version with no prebuilt falls back to `ghcup install ghc <version>`.
#
# Hermetic: ghcup is a stub that logs its arguments, and CB_PREBUILT_URL points at a
# fake release tree served as file://. Linux only: the prebuilt asset name comes
# from /etc/os-release, as in the image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/variants/base/setups/libs/ghc-source.sh"

if [ "$(uname -s)" != Linux ] || ! command -v sha256sum >/dev/null 2>&1; then
    echo "SKIP: needs Linux with sha256sum (prebuilt asset names come from /etc/os-release)"
    exit 0
fi

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CB_PREBUILT_URL="file://$TMP/release"
# shellcheck source=/dev/null
source "$LIB"

# A fake prebuilt GHC 9.10.3, laid out like the real one: wrappers that name the
# build prefix /opt/ghc/ghc-9.10.3.
name="$(cb_prebuilt_asset ghc 9.10.3 native)"
stage="$TMP/stage/$name"
mkdir -p "$stage/bin" "$stage/lib" "$TMP/release/ghc-9.10.3"
for f in ghc-9.10.3 ghc-pkg-9.10.3 haddock-ghc-9.10.3; do
    printf '#!/bin/sh\nexedir="/opt/ghc/ghc-9.10.3/lib/bin"\nexec "$exedir/%s" "$@"\n' "$f" > "$stage/bin/$f"
    chmod +x "$stage/bin/$f"
done
ln -s ghc-9.10.3 "$stage/bin/ghc"
tar -czf "$TMP/release/ghc-9.10.3/$name.tar.gz" -C "$TMP/stage" "$name"
(cd "$TMP/release/ghc-9.10.3" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")

# A stub ghcup in <tree>/.ghcup/bin that logs its calls and lists two versions.
make_ghcup() {  # make_ghcup <tree>
    mkdir -p "$1/.ghcup/bin"
    cat > "$1/.ghcup/bin/ghcup" <<STUB
#!/bin/sh
echo "\$*" >> "$1/ghcup.log"
case "\$*" in
  "list -t ghc -c available -r"|"list -t ghc -c installed -r")
    echo "ghc 9.10.3 recommended,base-4.20.1.0 hls-powered"
    echo "ghc 9.8.4 base-4.19.2.0 hls-powered" ;;
esac
STUB
    chmod +x "$1/.ghcup/bin/ghcup"
    : > "$1/ghcup.log"
}

# 1. recommended → 9.10.3 → prebuilt
T1="$TMP/tree1"; make_ghcup "$T1"
out="$(cb_ghc_install "$T1/.ghcup/bin/ghcup" recommended 2>&1 && echo "VERSION=$CB_GHC_VERSION")" || true
G="$T1/.ghcup/ghc/9.10.3"
problems=()
[[ "$out" == *"VERSION=9.10.3"* ]]                            || problems+=("CB_GHC_VERSION is not 9.10.3")
[ -x "$G/bin/ghc-9.10.3" ]                                    || problems+=("no $G/bin/ghc-9.10.3")
grep -q "exedir=\"$G/lib/bin\"" "$G/bin/ghc-9.10.3"           || problems+=("wrapper still names the build prefix")
! grep -rq /opt/ghc/ghc-9.10.3 "$G/bin"                       || problems+=("a wrapper still names /opt/ghc/ghc-9.10.3")
[ "$(readlink "$T1/.ghcup/bin/ghc-9.10.3")" = ../ghc/9.10.3/bin/ghc-9.10.3 ] || problems+=("no ghc-9.10.3 link")
[ "$(readlink "$T1/.ghcup/bin/ghc-9.10")" = ../ghc/9.10.3/bin/ghc-9.10.3 ]   || problems+=("no ghc-9.10 link")
[ "$(readlink "$T1/.ghcup/bin/haddock-9.10.3")" = ../ghc/9.10.3/bin/haddock-ghc-9.10.3 ] || problems+=("no haddock-9.10.3 link")
! grep -q '^install' "$T1/ghcup.log"                          || problems+=("ghcup install ran anyway")
if [ ${#problems[@]} -eq 0 ]; then
    report true "a tag resolves to a prebuilt GHC: unpacked, wrappers relocated, versioned links, no ghcup install"
else
    report false "a tag resolves to a prebuilt GHC" "${problems[@]}" "$out" "ghcup log: $(cat "$T1/ghcup.log")"
fi

# 2. 9.8.4 has no prebuilt → ghcup install ghc 9.8.4
T2="$TMP/tree2"; make_ghcup "$T2"
out="$(cb_ghc_install "$T2/.ghcup/bin/ghcup" 9.8.4 2>&1 && echo "VERSION=$CB_GHC_VERSION")" || true
if grep -qx 'install ghc 9.8.4' "$T2/ghcup.log" && [[ "$out" == *"VERSION=9.8.4"* ]] \
   && [ ! -e "$T2/.ghcup/ghc/9.8.4" ]; then
    report true "a version with no prebuilt falls back to ghcup install"
else
    report false "a version with no prebuilt falls back to ghcup install" "$out" "ghcup log: $(cat "$T2/ghcup.log")"
fi

if [ "$ALL_PASSED" = true ]; then
    exit 0
else
    exit 1
fi
