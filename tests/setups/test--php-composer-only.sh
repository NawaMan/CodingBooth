#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# --composer-only must install Composer without reinstalling PHP (no apt-get,
# no rm -rf of the PHP prefix). A missing php on PATH must fail, because the
# installer is `php composer-setup.php`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHP_SCRIPT="$REPO_ROOT/variants/base/setups/php--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/empty"

cat > "$STUB/bin/curl" << 'EOF'
#!/bin/bash
echo "STUB_CURL $*" >> "$STUB_LOG"
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -o*) out="${1#-o}" ;;
    esac
    shift || true
done
if [[ -n "$out" ]]; then
    : > "$out"
fi
EOF
chmod +x "$STUB/bin/curl"

cat > "$STUB/bin/php" << 'EOF'
#!/bin/bash
echo "STUB_PHP $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/php"

cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/apt-get"

run_php_setup() {
    local path="$1"; shift
    : > "$STUB/log"
    # Absolute /usr/bin/env so PATH can omit /usr/bin (test 2 hides host php).
    PATH="$path" STUB_LOG="$STUB/log" \
        /usr/bin/env EUID=0 bash "$PHP_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# 1. --composer-only with php on PATH: curl the installer, run it, never apt-get.
out=$(run_php_setup "$STUB/bin:$PATH" --composer-only) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] \
    && grep -q "getcomposer.org/installer" "$STUB/log" \
    && grep -q "STUB_PHP /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer" "$STUB/log" \
    && ! grep -q "STUB_APT" "$STUB/log"; then
    print_test_result "true" "$0" "1" "--composer-only installs Composer without apt-get"
else
    print_test_result "false" "$0" "1" "--composer-only installs Composer without apt-get"
    echo "  rc=$rc"
    echo "  stub log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

# 2. --composer-only without php: fail, and still no apt-get.
# /bin for bash; omit /usr/bin so a host php (usually /usr/bin/php) is hidden.
out=$(run_php_setup "$STUB/empty:/bin" --composer-only) && rc=0 || rc=$?
if [[ $rc -ne 0 ]] \
    && echo "$out" | grep -q "php on PATH" \
    && ! grep -q "STUB_APT" "$STUB/log"; then
    print_test_result "true" "$0" "2" "--composer-only fails when php is missing"
else
    print_test_result "false" "$0" "2" "--composer-only fails when php is missing"
    echo "  rc=$rc (want non-zero)"
    echo "  stub log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
