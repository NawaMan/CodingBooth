#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb-check-tar-extract.sh
#
# The helper test-extracts a one-file archive before a setup unpacks a real
# tarball. Under Docker Desktop's Rosetta amd64 emulation on Apple Silicon,
# Ubuntu's tar fails every extraction (it needs openat2, which Rosetta does not
# implement), and the helper has to turn that into one actionable message.
#
# Rosetta is not reproducible here, so tar and perl are stubbed: a tar that
# fails on -x stands in for the broken extraction, and a perl that exits 0 or 1
# stands in for the openat2 ENOSYS probe. The "tar works" case uses the host's
# real tar (bsdtar on macOS, GNU tar on Linux).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/variants/base/setups/cb-check-tar-extract.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/broken-tar" "$STUB/enosys" "$STUB/no-enosys"

# A tar that creates archives normally but fails every extraction, the way
# Ubuntu's tar does under Rosetta.
REAL_TAR="$(command -v tar)"
cat > "$STUB/broken-tar/tar" <<EOF
#!/bin/bash
case "\$1" in
  -x*|x*) echo "tar: src/probe: Cannot open: Function not implemented" >&2; exit 2 ;;
esac
exec "$REAL_TAR" "\$@"
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUB/enosys/perl"      # openat2 -> ENOSYS
printf '#!/bin/bash\nexit 1\n' > "$STUB/no-enosys/perl"   # openat2 is available
chmod +x "$STUB/broken-tar/tar" "$STUB/enosys/perl" "$STUB/no-enosys/perl"

ALL_PASSED=true
TEST_NUM=0

# Sets RUN_OUT and RUN_EXIT rather than returning them, since a failing exit
# status (two of the three cases) must not trip this script's own `set -e`.
RUN_OUT=""
RUN_EXIT=0
run_helper() {
    local path="$1"
    RUN_OUT=$(PATH="$path" bash "$HELPER" 2>&1) && RUN_EXIT=0 || RUN_EXIT=$?
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if grep -qF -- "$needle" <<<"$haystack"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc (missing: '$needle')"
        echo "$haystack" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if grep -qF -- "$needle" <<<"$haystack"; then
        print_test_result "false" "$0" "$TEST_NUM" "$desc (unexpectedly present: '$needle')"
        echo "$haystack" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    else
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    fi
}

assert_exit_eq() {
    local desc="$1" expected="$2" actual="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$actual" -eq "$expected" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc (exit=$actual, expected=$expected)"
        ALL_PASSED=false
    fi
}

ROSETTA_MSG="the openat2 system call is not implemented"
ROSETTA_FIX="Use Rosetta for x86_64/amd64"
GENERIC_MSG="a test extraction failed"

# ---- tar works: silent success ----------------------------------------------
run_helper "$PATH"
assert_exit_eq "exits 0 when tar extracts" 0 "$RUN_EXIT"
TEST_NUM=$((TEST_NUM + 1))
if [[ -z "$RUN_OUT" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "prints nothing when tar extracts"
else
    print_test_result "false" "$0" "$TEST_NUM" "prints nothing when tar extracts (got: '$RUN_OUT')"
    ALL_PASSED=false
fi

# ---- tar fails and openat2 is ENOSYS: the Rosetta explanation --------------
run_helper "$STUB/broken-tar:$STUB/enosys:$PATH"
assert_exit_eq  "exits 1 when extraction fails under missing openat2" 1 "$RUN_EXIT"
assert_contains "names the missing openat2 call"                      "$RUN_OUT" "$ROSETTA_MSG"
assert_contains "names the Docker Desktop setting to turn off"         "$RUN_OUT" "$ROSETTA_FIX"
assert_not_contains "does not also print the generic message"          "$RUN_OUT" "$GENERIC_MSG"

# ---- tar fails for another reason: the generic message ---------------------
run_helper "$STUB/broken-tar:$STUB/no-enosys:$PATH"
assert_exit_eq      "exits 1 when extraction fails with openat2 available" 1 "$RUN_EXIT"
assert_contains     "prints the generic failure"                          "$RUN_OUT" "$GENERIC_MSG"
assert_not_contains "does not blame Rosetta"                              "$RUN_OUT" "$ROSETTA_FIX"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
