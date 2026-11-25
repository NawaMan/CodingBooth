#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: go-nb-kernel--setup.sh installs goimports, pinned, from
# NawaMan/CodingBoothPrebuilt and compiles it only when there is no asset
#
#   1. An asset exists: its bin/goimports lands in the booth user's ~/go/bin
#      (where go install puts it), and goimports is never go-installed.
#   2. No asset: go install runs for the pinned golang.org/x/tools version,
#      never @latest.
#
# Hermetic: CB_PREBUILT_URL points at a file:// release folder this test writes,
# so the download, sha256 check and unpack are the real ones. go, sudo, id,
# install, mktemp and rm are stubs; python passes the Jupyter check and then
# fails `jupyter kernelspec install`, so each run stops right after goimports.
# GoNB itself has no asset here and takes its go install fallback. Nothing is
# downloaded, installed, or written outside the stub directory.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/go-nb-kernel--setup.sh"

# The version the setup pins, read from it so a bump does not break this test.
PIN="$(sed -n 's/^GOIMPORTS_VER="\(.*\)"$/\1/p' "$SCRIPT")"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap '/bin/rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/tmp" "$STUB/releases" "$STUB/empty" "$STUB/home/go/bin"
LOG="$STUB/calls.log"
DISTRO="$( (. /etc/os-release && echo "${ID}${VERSION_ID}") 2>/dev/null || true)"

# A release folder holding a real goimports tarball and its .sha256.
name="goimports-${PIN}-${DISTRO}-arm64"
mkdir -p "$STUB/pkg/$name/bin" "$STUB/releases/goimports-${PIN}"
printf '#!/bin/sh\necho prebuilt-goimports\n' > "$STUB/pkg/$name/bin/goimports"
chmod +x "$STUB/pkg/$name/bin/goimports"
tar -czf "$STUB/releases/goimports-${PIN}/$name.tar.gz" -C "$STUB/pkg" "$name"
(cd "$STUB/releases/goimports-${PIN}" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")

# sudo -u <user> bash -lc "<cmd>": log the command and leave gonb where go install puts it.
cat > "$STUB/bin/sudo" <<'STUBEOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
touch "$CB_USER_HOME/go/bin/gonb"; chmod +x "$CB_USER_HOME/go/bin/gonb"
STUBEOF
cat > "$STUB/bin/python" <<'STUBEOF'
#!/bin/bash
[[ "$1" == - ]] && exit 0
echo "python $*" >> "$STUB_LOG"
echo "STOP: stub python" >&2
exit 1
STUBEOF
cat > "$STUB/bin/install" <<'STUBEOF'
#!/bin/bash
echo "install $*" >> "$STUB_LOG"
STUBEOF
cat > "$STUB/bin/rm" <<'STUBEOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    -*) ;;
    "$STUB_ROOT"/*) /bin/rm -rf "$a" ;;
  esac
done
STUBEOF
cat > "$STUB/bin/mktemp" <<'STUBEOF'
#!/bin/bash
exec /usr/bin/mktemp -d "$STUB_ROOT/tmp/gonb.XXXXXX"
STUBEOF
cat > "$STUB/bin/uname" <<'STUBEOF'
#!/bin/bash
echo aarch64
STUBEOF
printf '#!/bin/bash\nexit 0\n' > "$STUB/bin/go"
printf '#!/bin/bash\necho coder\n' > "$STUB/bin/id"
chmod +x "$STUB/bin/"*

run_setup() { # release folder; prints the output, sets RC
    : > "$LOG"
    /bin/rm -f "$STUB/home/go/bin/"*
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin:/sbin" STUB_LOG="$LOG" STUB_ROOT="$STUB" \
        CB_PREBUILT_URL="file://$1" CB_USER_NAME=coder CB_USER_HOME="$STUB/home" \
        "$SCRIPT" 2>&1) || RC=$?
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

if [[ -z "$PIN" ]]; then
    RC=0; OUT="no GOIMPORTS_VER=\"x.y.z\" line in $SCRIPT"; : > "$LOG"
    check 0 "the setup pins goimports" false
    exit 1
fi

run_setup "$STUB/empty"
ok=false
echo "$OUT" | grep -q "goimports ${PIN}: not prebuilt for this image; building with go install" &&
  grep -q "^sudo -u coder bash -lc go install golang.org/x/tools/cmd/goimports@v${PIN}$" "$LOG" &&
  ! grep -q "goimports@latest" "$LOG" && grep -q "^python -m jupyter kernelspec install" "$LOG" && ok=true
check 2 "no asset falls back to go install of the pinned x/tools v${PIN}" "$ok"

# The asset is named after /etc/os-release (ubuntu26.04), which only Linux has.
if [[ -r /etc/os-release ]]; then
    run_setup "$STUB/releases"
    ok=false
    grep -q "^install -m 755 -o coder -g coder $STUB/tmp/gonb\..*/goimports/bin/goimports $STUB/home/go/bin/goimports$" "$LOG" &&
      ! grep -q "go install golang.org/x/tools" "$LOG" && grep -q "^python -m jupyter kernelspec install" "$LOG" && ok=true
    check 1 "a prebuilt asset lands in ~/go/bin, with no go install of goimports" "$ok"
else
    echo "SKIP: test 1 needs /etc/os-release for the CodingBoothPrebuilt asset name ($(uname -s))"
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
