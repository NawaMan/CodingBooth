#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: brew--install.sh treats a warning-exit as success when the
# formulae are actually installed.
#
# Linuxbrew's `brew install nginx,postgresql,redis` often exits 1 after a
# successful install because those formulae "provide a service which can only
# be used on macOS or systemd", or because nginx is shadowed by /usr/sbin.
# homebrew-example's image build died on that. The script must still fail
# when a formula is genuinely missing.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BREW_SCRIPT="$REPO_ROOT/variants/base/setups/brew--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/linuxbrew/bin"
MARKER="$STUB/invoked.log"

cat > "$STUB/bin/sudo" << 'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do
    case "$1" in
        -u) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
exec "$@"
EOF

cat > "$STUB/bin/chown" << 'EOF'
#!/bin/bash
exit 0
EOF
cat > "$STUB/bin/chmod" << 'EOF'
#!/bin/bash
exit 0
EOF

cat > "$STUB/linuxbrew/bin/brew" << 'EOF'
#!/bin/bash
echo "brew $*" >> "${STUB_LOG:?}"
cmd="$1"
shift
case "$cmd" in
    install) exit "${BREW_INSTALL_RC:-0}" ;;
    list)    exit "${BREW_LIST_RC:-0}" ;;
    *)       exit 0 ;;
esac
EOF
chmod +x "$STUB/bin/sudo" "$STUB/bin/chown" "$STUB/bin/chmod" "$STUB/linuxbrew/bin/brew"

run_brew_install() {
    PATH="$STUB/bin:$PATH" \
    STUB_LOG="$MARKER" \
    LINUXBREW_PREFIX="$STUB/linuxbrew" \
    SETUP_LIBS_DIR="$REPO_ROOT/variants/base/setups/libs" \
    CB_RETRY_ATTEMPTS=1 \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$BREW_SCRIPT" "$@" 2>&1
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

# 1. brew install exits 0 → success, list is not consulted.
: > "$MARKER"
OUT=$(BREW_INSTALL_RC=0 run_brew_install nginx) || RC=$?
RC=${RC:-0}
if [ "$RC" -eq 0 ] && grep -q "brew install nginx" "$MARKER"; then
    pass_fail true "a clean brew install exits 0"
else
    pass_fail false "a clean brew install exits 0" "rc=$RC out=$OUT"
fi

# 2. brew install exits 1 but `brew list` finds the formula → warning, exit 0.
: > "$MARKER"
RC=0
OUT=$(BREW_INSTALL_RC=1 BREW_LIST_RC=0 run_brew_install nginx postgresql) || RC=$?
if [ "$RC" -eq 0 ] && grep -q "all requested packages are present" <<< "$OUT"; then
    pass_fail true "a warning-exit with formulae present is not a failed install"
else
    pass_fail false "a warning-exit with formulae present is not a failed install" "rc=$RC out=$OUT"
fi

# 3. brew install exits 1 and `brew list` misses a formula → fail.
: > "$MARKER"
RC=0
OUT=$(BREW_INSTALL_RC=1 BREW_LIST_RC=1 run_brew_install nginx) || RC=$?
if [ "$RC" -ne 0 ] && grep -q "these packages are missing: nginx" <<< "$OUT"; then
    pass_fail true "a missing formula still fails the install"
else
    pass_fail false "a missing formula still fails the install" "rc=$RC out=$OUT"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
