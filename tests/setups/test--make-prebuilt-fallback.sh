#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: make--setup.sh takes a pinned release from NawaMan/CodingBoothPrebuilt
# and builds it from source only when there is no asset
#
#   1. No asset for the version: the script says so, and goes on to install the
#      build tools (the source build's first step).
#   2. The asset downloads but its sha256 does not match: the setup fails, and
#      builds nothing from source.
#   3. --version apt (the template's default) installs Ubuntu's package and
#      downloads nothing.
#
# Hermetic: curl, apt-get, uname, sha256sum, mktemp, rm and ln are stubs that log
# their arguments. apt-get fails its install, so each path stops right after
# showing itself; rm only removes inside the stub directory. Nothing is
# downloaded, installed, or written outside it.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/make--setup.sh"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/tmp"
LOG="$STUB/calls.log"

# curl: CURL_MODE=fail fails every download; ok writes the file -o names.
cat > "$STUB/bin/curl" <<'STUBEOF'
#!/bin/bash
echo "curl $*" >> "$STUB_LOG"
[[ "$CURL_MODE" == fail ]] && { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
out=""
while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
[[ -n "$out" ]] && echo "stub-content" > "$out"
exit 0
STUBEOF
cat > "$STUB/bin/apt-get" <<'STUBEOF'
#!/bin/bash
echo "apt-get $*" >> "$STUB_LOG"
[[ "$1" == install ]] && exit 1
exit 0
STUBEOF
cat > "$STUB/bin/uname" <<'STUBEOF'
#!/bin/bash
echo aarch64
STUBEOF
cat > "$STUB/bin/sha256sum" <<'STUBEOF'
#!/bin/bash
echo "1111111111111111111111111111111111111111111111111111111111111111  $1"
STUBEOF
cat > "$STUB/bin/mktemp" <<'STUBEOF'
#!/bin/bash
exec /usr/bin/mktemp -d "$STUB_ROOT/tmp/make-build.XXXXXX"
STUBEOF
cat > "$STUB/bin/rm" <<'STUBEOF'
#!/bin/bash
echo "rm $*" >> "$STUB_LOG"
for a in "$@"; do
  case "$a" in
    -*) ;;
    "$STUB_ROOT"/*) /bin/rm -rf "$a" ;;
  esac
done
STUBEOF
cat > "$STUB/bin/ln" <<'STUBEOF'
#!/bin/bash
echo "ln $*" >> "$STUB_LOG"
STUBEOF
chmod +x "$STUB/bin/"*

run_setup() { # CURL_MODE version; prints the output, sets RC
    : > "$LOG"
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin" STUB_LOG="$LOG" STUB_ROOT="$STUB" CURL_MODE="$1" \
        "$SCRIPT" --version "$2" 2>&1) || RC=$?
}

FAILED=0
check() { # number, description, ok (true|false)
    print_test_result "$3" "$0" "$1" "$2"
    if [[ "$3" != "true" ]]; then
        echo "  rc=$RC"
        echo "$OUT" | sed 's/^/  out: /' | tail -8
        sed 's/^/  log: /' "$LOG" | tail -8
        FAILED=$((FAILED + 1))
    fi
}

run_setup fail 4.4.1
ok=false
grep -q "CodingBoothPrebuilt/releases/download/make-4.4.1/make-4.4.1-.*-arm64.tar.gz" "$LOG" &&
  echo "$OUT" | grep -q "GNU Make 4.4.1: not prebuilt for this image; building from source" &&
  grep -q "^apt-get install .*build-essential" "$LOG" && ok=true
check 1 "a release with no prebuilt asset falls back to the source build" "$ok"

run_setup ok 4.4.1
ok=false
[[ "$RC" -ne 0 ]] && echo "$OUT" | grep -q "does not match the release's" &&
  ! echo "$OUT" | grep -q "building from source" && ! grep -q "build-essential" "$LOG" && ok=true
check 2 "a sha256 mismatch stops the setup, with no source build" "$ok"

run_setup ok apt
ok=false
! grep -q "^curl " "$LOG" && grep -q "^apt-get install .* make$" "$LOG" &&
  ! grep -q "build-essential" "$LOG" && ok=true
check 3 "--version apt installs Ubuntu's package and downloads nothing" "$ok"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
