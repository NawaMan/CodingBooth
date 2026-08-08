#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: lombok-idea--setup.sh
#
# The script's entire job is to name one plugin correctly, so that is what this
# checks: it runs the real script with jetbrains-plugin--install.sh stubbed, and
# asserts the exact argument vector handed over.
#
# Locked in here:
#   - the id is Lombok's xmlId, "Lombook Plugin" (JetBrains' own misspelling)
#   - it is passed as EXACTLY ONE argument. Passing it unquoted would deliver two
#     arguments, "Lombook" and "Plugin", both of which the marketplace rejects —
#     and the whole reason this curated script exists is to keep the numeric id out
#     of the Boothfile, so silently regressing to a broken name would defeat it.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"

ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy lombok-idea--setup.sh's root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT

# The script resolves its sibling by dirname "$0", so copy it next to a stub installer
# that records what it was called with, one argument per line.
cp "$SETUPS_DIR/lombok-idea--setup.sh" "$STUB/"
cat > "$STUB/jetbrains-plugin--install.sh" << EOF
#!/bin/bash
: > "$STUB/argv.txt"
for a in "\$@"; do printf '%s\n' "\$a" >> "$STUB/argv.txt"; done
EOF
chmod +x "$STUB/jetbrains-plugin--install.sh" "$STUB/lombok-idea--setup.sh"

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = "true" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [ -n "$detail" ] && echo "$detail" | sed 's/^/          /'
        ALL_PASSED=false
    fi
}

OUT=$(${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$STUB/lombok-idea--setup.sh" < /dev/null 2>&1) && RC=0 || RC=$?
check "the setup exits 0" "$([ $RC -eq 0 ] && echo true || echo false)" "$OUT"

ARGC=$(wc -l < "$STUB/argv.txt" 2>/dev/null || echo 0)
check "exactly one argument is passed" \
      "$([ "$ARGC" = "1" ] && echo true || echo false)" \
      "argv: $(cat "$STUB/argv.txt" 2>/dev/null)"

check "that argument is Lombok's xmlId" \
      "$([ "$(head -1 "$STUB/argv.txt" 2>/dev/null)" = "Lombook Plugin" ] && echo true || echo false)" \
      "argv[0]: $(head -1 "$STUB/argv.txt" 2>/dev/null)"

# --help must not install anything — it is documentation, not a dry run.
: > "$STUB/argv.txt"
${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$STUB/lombok-idea--setup.sh" --help >/dev/null 2>&1 || true
check "--help installs nothing" \
      "$([ ! -s "$STUB/argv.txt" ] && echo true || echo false)" \
      "argv: $(cat "$STUB/argv.txt" 2>/dev/null)"

if [ "$ALL_PASSED" != "true" ]; then
    exit 1
fi
