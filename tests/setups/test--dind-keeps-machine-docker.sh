#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: dind--setup.sh keeps a machine's own Docker off a booth
#
# In a booth (CB_TARGET unset or booth) the setup installs docker.io, the client
# for the DinD sidecar. Off a booth (gha/host) with docker already on PATH it
# installs socat only, since docker.io would replace docker-ce and stop the
# machine's daemon. Without docker on PATH it installs docker.io there too.
#
# sudo is a stub that logs and runs nothing, and the EUID is faked; the script
# then stops at its first write under /usr/local/bin, after the apt step this
# test is about. Skipped when really run as root, where those writes would land.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

SCRIPT="$(cd "$SCRIPT_DIR/../.." && pwd)/variants/base/setups/dind--setup.sh"

if [[ "$(id -u)" -eq 0 ]]; then
    echo "SKIP: running as root; the setup would write to /usr/local/bin"
    exit 0
fi

STUB=$(mktemp -d)
trap "rm -rf '$STUB'" EXIT
mkdir -p "$STUB/with-docker" "$STUB/no-docker"
cat > "$STUB/sudo" << 'EOF2'
#!/bin/bash
echo "STUB_SUDO $*" >> "$STUB_LOG"
EOF2
cat > "$STUB/with-docker/docker" << 'EOF2'
#!/bin/bash
echo "Docker version 29.0.0, build stub"
EOF2
chmod +x "$STUB/sudo" "$STUB/with-docker/docker"
cp "$STUB/sudo" "$STUB/no-docker/sudo"; cp "$STUB/sudo" "$STUB/with-docker/sudo"
# Only the tools the script needs, so a real docker on this host stays out of sight.
mkdir -p "$STUB/tools"
for tool in bash cat chmod mkdir env id; do
    real=$(command -v "$tool") || { echo "FAIL: '$tool' not found on PATH" >&2; exit 1; }
    ln -s "$real" "$STUB/tools/$tool"
done

# run_setup <docker-dir> <CB_TARGET or "">: log of the sudo calls
run_setup() {
    : > "$STUB/log"
    PATH="$STUB/$1:$STUB/tools" STUB_LOG="$STUB/log" CB_TARGET="$2" \
        "$STUB/tools/env" EUID=0 bash "$SCRIPT" > /dev/null 2>&1 || true
    grep 'apt-get install' "$STUB/log" || true
}

ALL_PASSED=true
check() {   # check <n> <label> <docker-dir> <CB_TARGET> <expected install line>
    local got; got="$(run_setup "$3" "$4")"
    if [[ "$got" == "$5" ]]; then
        print_test_result "true" "$0" "$1" "$2"
    else
        print_test_result "false" "$0" "$1" "$2"
        echo "  expected: $5"; echo "  got:      $got"
        ALL_PASSED=false
    fi
}

check 1 "in a booth: installs docker.io"                    with-docker ""     "STUB_SUDO apt-get install -y socat docker.io"
check 2 "CB_TARGET=booth: installs docker.io"               with-docker booth  "STUB_SUDO apt-get install -y socat docker.io"
check 3 "gha with docker: keeps it, socat only"             with-docker gha    "STUB_SUDO apt-get install -y socat"
check 4 "host with docker: keeps it, socat only"            with-docker host   "STUB_SUDO apt-get install -y socat"
check 5 "gha without docker: installs docker.io"            no-docker   gha    "STUB_SUDO apt-get install -y socat docker.io"

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
