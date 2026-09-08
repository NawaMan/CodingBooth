#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: apt--install.sh retries an apt-get update that 5xx'd the snapshot
# and still exited 0.
#
# Ubuntu's snapshot service 502/503s; apt-get update prints
# "W: Failed to fetch … ignored" and returns success. cb_retry used to take
# that as a clean update, then apt-get install died with
# "E: Unable to locate package ripgrep" — wording we refuse to retry, so the
# blip became a hard, misleading build failure (apt-example, turtle-example,
# systemlib-example in the same suite run).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APT_SCRIPT="$REPO_ROOT/variants/base/setups/apt--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
MARKER="$STUB/invoked.log"
STATE="$STUB/state"
mkdir -p "$STATE"

cat > "$STUB/apt-get" << 'EOF'
#!/bin/bash
echo "apt-get $*" >> "${STUB_LOG:?}"
cmd="$1"
shift
if [ "$cmd" = update ]; then
    n=$(cat "${STUB_STATE:?}/update.n" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$STUB_STATE/update.n"
    if [ "$n" -le "${FAIL_UPDATES:-0}" ]; then
        echo "Ign:20 https://snapshot.ubuntu.com/ubuntu/20260908T000000Z noble InRelease"
        echo "Err:20 https://snapshot.ubuntu.com/ubuntu/20260908T000000Z noble InRelease"
        echo "  503  Service Unavailable [IP: 185.125.189.37 443]"
        echo "W: Failed to fetch https://snapshot.ubuntu.com/ubuntu/20260908T000000Z/dists/noble/InRelease  503  Service Unavailable [IP: 185.125.189.37 443]"
        echo "W: Some index files failed to download. They have been ignored, or old ones used instead."
        exit 0
    fi
    echo "Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease"
    echo "Reading package lists..."
    exit 0
fi
if [ "$cmd" = install ]; then
    echo "install $*"
    exit "${APT_INSTALL_RC:-0}"
fi
exit 0
EOF

cat > "$STUB/rm" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB/apt-get" "$STUB/rm"

run_apt_install() {
    : > "$MARKER"
    rm -f "$STATE"/*.n
    PATH="$STUB:$PATH" \
    STUB_LOG="$MARKER" \
    STUB_STATE="$STATE" \
    SETUP_LIBS_DIR="$REPO_ROOT/variants/base/setups/libs" \
    CB_RETRY_DELAY=0 \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$APT_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true
TEST_NUM=0

pass_fail() {
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc" "$@"
        ALL_PASSED=false
    fi
}

updates() { grep -c "^apt-get update" "$MARKER" || true; }
installs() { grep -c "^apt-get install" "$MARKER" || true; }

# 1. Clean update — one update, one install.
RC=0
OUT=$(FAIL_UPDATES=0 run_apt_install jq) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(updates)" = 1 ] && [ "$(installs)" = 1 ]; then
    pass_fail true "a clean apt-get update is not retried"
else
    pass_fail false "a clean apt-get update is not retried" "rc=$RC updates=$(updates) installs=$(installs)" "$OUT"
fi

# 2. Snapshot 503 with exit 0 — retried, then install proceeds.
RC=0
OUT=$(FAIL_UPDATES=1 run_apt_install jq,ripgrep) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(updates)" = 2 ] && [ "$(installs)" = 1 ] \
   && grep -q "retrying in" <<< "$OUT"; then
    pass_fail true "a snapshot 503 that apt-get treated as success is retried"
else
    pass_fail false "a snapshot 503 that apt-get treated as success is retried" \
        "rc=$RC updates=$(updates) installs=$(installs)" "$OUT"
fi

# 3. Snapshot never comes back — fail after 3 updates, never install.
RC=0
OUT=$(FAIL_UPDATES=99 run_apt_install jq) || RC=$?
if [ "$RC" -ne 0 ] && [ "$(updates)" = 3 ] && [ "$(installs)" = 0 ]; then
    pass_fail true "a snapshot that never recovers fails after 3 updates and does not install"
else
    pass_fail false "a snapshot that never recovers fails after 3 updates and does not install" \
        "rc=$RC updates=$(updates) installs=$(installs)" "$OUT"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
