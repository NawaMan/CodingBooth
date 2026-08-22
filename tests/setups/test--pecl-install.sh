#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: pecl--install.sh extension-name derivation
#
# Runs the real pecl--install.sh with `pecl` and `php` stubbed, and asserts what
# it hands to pecl and what it names the .so / .ini it enables.
#
# The interesting case is a version pin. `pecl install redis-6.0.2` builds
# redis.so — the version is part of the request, never part of the extension
# name — so a script that reuses the whole spec as the basename fails its own
# post-install check and takes the image build with it. That is exactly what
# this script used to do, which is why the documented `-version` pin never
# worked. A name that merely contains a hyphen must survive untouched.
#
# The script requires root and an installed pecl; we satisfy those with a faked EUID
# plus a PHP_HOME override pointing at the stubs, so nothing real runs.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PECL_SCRIPT="$REPO_ROOT/variants/base/setups/pecl--install.sh"


STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/ext" "$STUB/scan"

# Stub pecl: echoes its argv, then creates the .so under the name a real pecl
# would build — STUB_SO, set per case. Keeping it a parameter rather than
# re-deriving the name here is the point: the test states independently what
# pecl produces, so the script cannot pass by agreeing with itself.
cat > "$STUB/bin/pecl" << 'EOF'
#!/bin/bash
echo "STUB_PECL $*"
touch "$STUB_EXT_DIR/${STUB_SO}.so"
EOF
chmod +x "$STUB/bin/pecl"

# Stub php: only `php -i` is used, for extension_dir and the .ini scan dir.
cat > "$STUB/bin/php" << 'EOF'
#!/bin/bash
echo "extension_dir => $STUB_EXT_DIR => $STUB_EXT_DIR"
echo "Scan this dir for additional .ini files => $STUB_SCAN_DIR"
EOF
chmod +x "$STUB/bin/php"

run_pecl_install() {
    local so="$1"; shift
    rm -f "$STUB/ext"/*.so "$STUB/scan"/*.ini
    PHP_HOME="$STUB" STUB_SO="$so" STUB_EXT_DIR="$STUB/ext" STUB_SCAN_DIR="$STUB/scan" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$PECL_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# assert_install <num> <desc> <so-name-pecl-builds> <spec> <expected-pecl-argv> <expected-ini>
assert_install() {
    local num="$1" desc="$2" so="$3" spec="$4" expect_argv="$5" expect_ini="$6"
    local out ok=true
    out=$(run_pecl_install "$so" "$spec") || ok=false
    if [[ "$ok" != true ]]; then
        print_test_result "false" "$0" "$num" "$desc"
        echo "  spec:   $spec (pecl builds ${so}.so)"
        echo "  script failed:"
        echo "$out" | sed 's/^/    /'
        ALL_PASSED=false
        return
    fi
    if ! echo "$out" | grep -qF -- "$expect_argv"; then
        print_test_result "false" "$0" "$num" "$desc"
        echo "  expected pecl argv: $expect_argv"
        echo "  actual:             $out"
        ALL_PASSED=false
        return
    fi
    if [[ ! -f "$STUB/scan/$expect_ini" ]]; then
        print_test_result "false" "$0" "$num" "$desc"
        echo "  expected ini: $expect_ini"
        echo "  actual:       $(ls "$STUB/scan")"
        ALL_PASSED=false
        return
    fi
    if ! grep -qF "extension=${so}.so" "$STUB/scan/$expect_ini"; then
        print_test_result "false" "$0" "$num" "$desc"
        echo "  expected: extension=${so}.so in $expect_ini"
        echo "  actual:   $(cat "$STUB/scan/$expect_ini")"
        ALL_PASSED=false
        return
    fi
    print_test_result "true" "$0" "$num" "$desc"
}

# 1. Plain extension: spec is the name, .so and .ini follow it.
assert_install 1 "plain extension installs and is enabled" \
    redis redis "STUB_PECL install redis" redis.ini

# 2. Version pin: the whole spec goes to pecl, the .so/.ini use the name only.
assert_install 2 "version pin reaches pecl but does not leak into the .so name" \
    redis redis-6.0.2 "STUB_PECL install redis-6.0.2" redis.ini

# 3. A PECL state tag is a version, not part of the name.
assert_install 3 "state tag is stripped from the .so name" \
    redis redis-beta "STUB_PECL install redis-beta" redis.ini

# 4. A hyphen that is not a version must survive.
assert_install 4 "hyphenated extension name is left alone" \
    my-ext my-ext "STUB_PECL install my-ext" my-ext.ini

# 5. …and such a name can still be pinned.
assert_install 5 "hyphenated name plus version strips only the version" \
    my-ext my-ext-1.2.3 "STUB_PECL install my-ext-1.2.3" my-ext.ini

# 6. An underscore name (the common PECL shape) is untouched.
assert_install 6 "underscore extension name is left alone" \
    pdo_mysql pdo_mysql "STUB_PECL install pdo_mysql" pdo_mysql.ini

# 7. A comma list is split per extension.
out=$(run_pecl_install redis redis,xdebug 2>&1) || true
if echo "$out" | grep -qF "STUB_PECL install redis" && echo "$out" | grep -qF "STUB_PECL install xdebug"; then
    print_test_result "true" "$0" "7" "comma list installs each extension"
else
    print_test_result "false" "$0" "7" "comma list installs each extension"
    echo "  actual: $out"
    ALL_PASSED=false
fi

# 8. No extensions requested is a no-op, not a failure (empty *_PKGS default).
if run_pecl_install redis "" | grep -q "No PECL extensions requested"; then
    print_test_result "true" "$0" "8" "empty package list is a no-op"
else
    print_test_result "false" "$0" "8" "empty package list is a no-op"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
