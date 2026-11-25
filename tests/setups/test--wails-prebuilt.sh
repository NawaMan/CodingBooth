#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: wails--setup.sh takes wails3 from NawaMan/CodingBoothPrebuilt and
# compiles it with go install only when there is no asset
#
#   1. An asset exists: its bin/wails3 is installed, and go install never runs.
#   2. No asset: the script says so and runs go install for that exact version.
#   3. --version latest is resolved through the Go module proxy to a concrete
#      version, so the asset it looks for is named after that version.
#   4. An unreachable proxy falls back to the known-good release (3.1.0).
#
# Hermetic: CB_PREBUILT_URL points at a file:// release folder this test writes,
# so the download, sha256 check and unpack are the real ones. apt-get,
# pkg-config, sudo, go, id, getent, rm and sleep are stubs; curl is passed
# through for file:// and answers proxy.golang.org itself. The `install` stub
# logs, and fails on /usr/local/bin/wails3, so each run stops right after
# showing which binary it would install. Nothing is downloaded, installed, or
# written outside the stub directory.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/wails--setup.sh"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap '/bin/rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/tmp" "$STUB/releases" "$STUB/home/go/bin"
LOG="$STUB/calls.log"
REAL_CURL="$(command -v curl)"

# The asset name the setup computes: <tool>-<ver>-<distro>-<arch>. uname is stubbed
# to aarch64; the distro comes from /etc/os-release, which is empty off Linux.
DISTRO="$( (. /etc/os-release && echo "${ID}${VERSION_ID}") 2>/dev/null || true)"

# publish <version>: a release folder holding a real tarball and its .sha256.
publish() {
    local ver="$1" name="wails3-$1-${DISTRO}-arm64" pkg="$STUB/pkg"
    /bin/rm -rf "$pkg"
    mkdir -p "$pkg/$name/bin" "$STUB/releases/wails3-$ver"
    printf '#!/bin/sh\necho "v%s (prebuilt stub)"\n' "$ver" > "$pkg/$name/bin/wails3"
    chmod +x "$pkg/$name/bin/wails3"
    tar -czf "$STUB/releases/wails3-$ver/$name.tar.gz" -C "$pkg" "$name"
    (cd "$STUB/releases/wails3-$ver" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
}

# curl: the module proxy is answered here (PROXY_MODE=ok|fail); everything else,
# the file:// release folder, goes to the real curl.
cat > "$STUB/bin/curl" <<'STUBEOF'
#!/bin/bash
echo "curl $*" >> "$STUB_LOG"
case "$*" in
  *proxy.golang.org*)
    [[ "$PROXY_MODE" == fail ]] && { echo "curl: (6) Could not resolve host" >&2; exit 6; }
    echo '{"Version":"v3.2.0","Time":"2026-11-20T00:00:00Z"}'
    exit 0 ;;
esac
exec "$REAL_CURL" "$@"
STUBEOF
cat > "$STUB/bin/install" <<'STUBEOF'
#!/bin/bash
echo "install $*" >> "$STUB_LOG"
[[ "${*: -1}" == /usr/local/bin/wails3 ]] && { echo "STOP: stub install" >&2; exit 1; }
exit 0
STUBEOF
# sudo -u <user> bash -lc "<cmd>": log the command and leave a wails3 where go install puts it.
cat > "$STUB/bin/sudo" <<'STUBEOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
touch "$CB_USER_HOME/go/bin/wails3"; chmod +x "$CB_USER_HOME/go/bin/wails3"
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
exec /usr/bin/mktemp -d "$STUB_ROOT/tmp/wails.XXXXXX"
STUBEOF
cat > "$STUB/bin/uname" <<'STUBEOF'
#!/bin/bash
echo aarch64
STUBEOF
for ok in apt-get pkg-config go getent sleep; do
    printf '#!/bin/bash\necho "%s $*" >> "$STUB_LOG"\nexit 0\n' "$ok" > "$STUB/bin/$ok"
done
printf '#!/bin/bash\necho coder\n' > "$STUB/bin/id"
chmod +x "$STUB/bin/"*

run_setup() { # PROXY_MODE version; prints the output, sets RC
    : > "$LOG"
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin:/sbin" STUB_LOG="$LOG" STUB_ROOT="$STUB" \
        REAL_CURL="$REAL_CURL" PROXY_MODE="$1" CB_PREBUILT_URL="file://$STUB/releases" \
        CB_USER_NAME=coder CB_USER_HOME="$STUB/home" \
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

run_setup ok 3.0.9
ok=false
echo "$OUT" | grep -q "wails3 3.0.9: not prebuilt for this image; building with go install" &&
  grep -q "^sudo -u coder bash -lc go install 'github.com/wailsapp/wails/v3/cmd/wails3@v3.0.9'$" "$LOG" &&
  grep -q "^install -m 755 $STUB/home/go/bin/wails3 /usr/local/bin/wails3$" "$LOG" && ok=true
check 2 "no asset falls back to go install of that exact version" "$ok"

# The asset is named after /etc/os-release (ubuntu26.04), which only Linux has: without
# it every lookup is "no asset", so the prebuilt paths can only be seen there.
if [[ -r /etc/os-release ]]; then
    publish 3.1.0
    run_setup ok v3.1.0
    ok=false
    grep -q "^install -m 755 $STUB/tmp/wails\..*/bin/wails3 /usr/local/bin/wails3$" "$LOG" &&
      ! grep -q "^sudo " "$LOG" && echo "$OUT" | grep -q "Installed prebuilt wails3-3.1.0-" && ok=true
    check 1 "a prebuilt asset is installed, with no go install" "$ok"

    run_setup ok latest
    ok=false
    grep -q "^curl .*proxy.golang.org/github.com/wailsapp/wails/v3/@latest" "$LOG" &&
      grep -q "^curl .*/wails3-3.2.0/wails3-3.2.0-${DISTRO}-arm64.tar.gz" "$LOG" &&
      grep -q "go install 'github.com/wailsapp/wails/v3/cmd/wails3@v3.2.0'" "$LOG" && ok=true
    check 3 "latest is resolved through the module proxy before looking for an asset" "$ok"

    run_setup fail latest
    ok=false
    echo "$OUT" | grep -q "Could not resolve the latest wails3 from proxy.golang.org; using 3.1.0" &&
      grep -q "^install -m 755 $STUB/tmp/wails\..*/bin/wails3 /usr/local/bin/wails3$" "$LOG" &&
      ! grep -q "^sudo " "$LOG" && ok=true
    check 4 "an unreachable proxy falls back to 3.1.0 (and its prebuilt asset)" "$ok"
else
    echo "SKIP: tests 1, 3, 4 need /etc/os-release for the CodingBoothPrebuilt asset name ($(uname -s))"
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
