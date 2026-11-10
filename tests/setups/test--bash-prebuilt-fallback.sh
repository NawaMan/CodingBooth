#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: bash--setup.sh falls back to a source build when the prebuilt 3.2
# cannot be downloaded, and only then
#
# The prebuilt from NawaMan/Bash32Ubuntu is a shortcut. A GitHub 504 that lasted
# past curl's retries used to fail the image build; the release is now built
# from source instead. A checksum mismatch is different -- the file arrived, and
# it is wrong -- so that still stops the setup.
#
#   1. Both prebuilt downloads fail: the script says so, and goes on to install
#      the build tools (the source build's first step).
#   2. The prebuilt downloads use the wider retry window.
#   3. The download succeeds but the sha256 does not match: the setup fails, and
#      builds nothing from source.
#
# Hermetic: curl, apt-get, uname, sha256sum, mkdir, mktemp and rm are stubs that
# log their arguments. apt-get fails its install, so a fallback stops right after
# showing itself; rm only removes inside the stub directory. Nothing is
# downloaded, installed, or written outside it.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/bash--setup.sh"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/tmp"
LOG="$STUB/calls.log"

# curl: CURL_MODE=fail fails every download; ok writes the file -o names.
cat > "$STUB/bin/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$STUB_LOG"
[[ "$CURL_MODE" == fail ]] && { echo "curl: (22) The requested URL returned error: 504" >&2; exit 22; }
out=""
while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
[[ -n "$out" ]] && echo "stub-content" > "$out"
exit 0
EOF
cat > "$STUB/bin/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >> "$STUB_LOG"
[[ "$1" == install ]] && exit 1
exit 0
EOF
cat > "$STUB/bin/uname" <<'EOF'
#!/bin/bash
echo aarch64
EOF
cat > "$STUB/bin/sha256sum" <<'EOF'
#!/bin/bash
echo "1111111111111111111111111111111111111111111111111111111111111111  $1"
EOF
cat > "$STUB/bin/mkdir" <<'EOF'
#!/bin/bash
echo "mkdir $*" >> "$STUB_LOG"
EOF
cat > "$STUB/bin/mktemp" <<'EOF'
#!/bin/bash
exec /usr/bin/mktemp -d "$STUB_ROOT/tmp/bash-build.XXXXXX"
EOF
cat > "$STUB/bin/rm" <<'EOF'
#!/bin/bash
echo "rm $*" >> "$STUB_LOG"
for a in "$@"; do
  case "$a" in
    -*) ;;
    "$STUB_ROOT"/*) /bin/rm -rf "$a" ;;
  esac
done
EOF
chmod +x "$STUB/bin/"*

run_setup() { # CURL_MODE; prints the output, sets RC
    : > "$LOG"
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin" STUB_LOG="$LOG" STUB_ROOT="$STUB" CURL_MODE="$1" \
        "$SCRIPT" --version 3.2.57 2>&1) || RC=$?
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

run_setup fail
ok=false
grep -q "Bash32Ubuntu/releases/download/bash-3.2.57/bash-3.2.57-ubuntu26.04-arm64-static.tar.gz" "$LOG" &&
  echo "$OUT" | grep -q "building GNU Bash 3.2.57 from source instead" &&
  grep -q "^apt-get install .*build-essential" "$LOG" && ok=true
check 1 "a failed prebuilt download falls back to the source build" "$ok"

ok=false
[[ "$(grep -c "^curl .*--retry 5 --retry-delay 5 .*Bash32Ubuntu" "$LOG" || true)" -ge 1 ]] && ok=true
check 2 "the prebuilt download retries 5 times, 5s apart" "$ok"

run_setup ok
ok=false
[[ "$RC" -ne 0 ]] && echo "$OUT" | grep -q "does not match the release's" &&
  ! echo "$OUT" | grep -q "from source instead" && ! grep -q "build-essential" "$LOG" && ok=true
check 3 "a sha256 mismatch stops the setup, with no source build" "$ok"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
