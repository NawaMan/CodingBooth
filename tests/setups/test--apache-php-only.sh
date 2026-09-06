#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# --php-only must install libapache2-mod-php without reinstalling apache2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/apache--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/empty"

cat > "$STUB/bin/apache2" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB/bin/apache2"

cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/apt-get"

cat > "$STUB/bin/a2enmod" << 'EOF'
#!/bin/bash
echo "STUB_A2ENMOD $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/a2enmod"

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

out=$(run_setup "$STUB/bin:/bin" --php-only) && rc=0 || rc=$?
if grep -q "libapache2-mod-php" "$STUB/log" \
    && ! grep -qE "STUB_APT install .* apache2( |$)" "$STUB/log"; then
    print_test_result "true" "$0" "1" "--php-only installs mod_php without apache2"
else
    print_test_result "false" "$0" "1" "--php-only installs mod_php without apache2"
    echo "  rc=$rc"; echo "  log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  out:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

out=$(run_setup "$STUB/empty:/bin" --php-only) && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "Apache"; then
    print_test_result "true" "$0" "2" "--php-only fails when Apache is missing"
else
    print_test_result "false" "$0" "2" "--php-only fails when Apache is missing"
    echo "  rc=$rc"; echo "  out:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
