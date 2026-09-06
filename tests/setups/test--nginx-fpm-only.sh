#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# --fpm-only must install php-fpm without reinstalling nginx.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/nginx--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/empty" "$STUB/nginx/sites-available"

cat > "$STUB/bin/nginx" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB/bin/nginx"

cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/apt-get"

cat > "$STUB/bin/rm" << 'EOF'
#!/bin/bash
echo "STUB_RM $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/rm"

run_setup() {
    local path="$1"; shift
    : > "$STUB/log"
    PATH="$path" STUB_LOG="$STUB/log" \
        /usr/bin/env EUID=0 bash "$SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# Point the site file at the stub tree so we do not write /etc/nginx.
# The script hardcodes /etc/nginx; --fpm-only will fail to write if that
# dir is missing. Assert we attempted php-fpm install and never nginx install.
out=$(run_setup "$STUB/bin:/bin" --fpm-only) && rc=0 || rc=$?
if grep -q "php-fpm" "$STUB/log" && ! grep -qE "STUB_APT install .* nginx( |$)" "$STUB/log"; then
    print_test_result "true" "$0" "1" "--fpm-only installs php-fpm without nginx"
else
    print_test_result "false" "$0" "1" "--fpm-only installs php-fpm without nginx"
    echo "  rc=$rc"; echo "  log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  out:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

out=$(run_setup "$STUB/empty:/bin" --fpm-only) && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "nginx"; then
    print_test_result "true" "$0" "2" "--fpm-only fails when nginx is missing"
else
    print_test_result "false" "$0" "2" "--fpm-only fails when nginx is missing"
    echo "  rc=$rc"; echo "  out:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
