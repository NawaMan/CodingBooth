#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: lsp--install.sh dispatches each name to its lsp--<name>--setup.sh.
#
# The lsp template passes its variadic LSP_SERVERS as one comma-joined value,
# empty unless the user typed names. Each name is a server or a language alias,
# with an optional @version that becomes --version. An empty list must build
# cleanly; an unknown name must fail and say what exists.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# The dispatcher looks next to itself first, so a copy among stub setups runs
# the stubs instead of the real installers.
STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
cp "$REPO_ROOT/variants/base/setups/lsp--install.sh" "$STUB/"
MARKER="$STUB/invoked.log"
for name in marksman taplo pylsp clangd typescript; do
    cat > "$STUB/lsp--${name}--setup.sh" << EOF
#!/bin/bash
echo "${name} \$*" >> "$MARKER"
EOF
    chmod +x "$STUB/lsp--${name}--setup.sh"
done

run_install() {
    ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$STUB/lsp--install.sh" "$@" 2>&1
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

# 1. Comma list, language aliases, and a version pin.
: > "$MARKER"
RC=0
OUT=$(run_install "markdown,toml@0.10.0" python) || RC=$?
EXPECTED=$'marksman \ntaplo --version 0.10.0\npylsp '
if [ "$RC" -eq 0 ] && [ "$(cat "$MARKER")" = "$EXPECTED" ]; then
    pass_fail true "names, aliases, and @version reach their setups in order"
else
    pass_fail false "names, aliases, and @version reach their setups in order" "rc=$RC calls=$(cat "$MARKER") out=$OUT"
fi

# 2. The C/C++ and React aliases.
: > "$MARKER"
RC=0
OUT=$(run_install cpp react) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(cat "$MARKER")" = $'clangd \ntypescript ' ]; then
    pass_fail true "cpp resolves to clangd and react to typescript"
else
    pass_fail false "cpp resolves to clangd and react to typescript" "rc=$RC calls=$(cat "$MARKER") out=$OUT"
fi

# 3. No names is a no-op, not a failed build.
: > "$MARKER"
RC=0
OUT=$(run_install "") || RC=$?
if [ "$RC" -eq 0 ] && [ ! -s "$MARKER" ] && grep -q "nothing to install" <<< "$OUT"; then
    pass_fail true "an empty list installs nothing and exits 0"
else
    pass_fail false "an empty list installs nothing and exits 0" "rc=$RC calls=$(cat "$MARKER") out=$OUT"
fi

# 4. An unknown name fails before anything runs past it, and lists what exists.
: > "$MARKER"
RC=0
OUT=$(run_install no-such-server) || RC=$?
if [ "$RC" -ne 0 ] && grep -q "Unknown language server: 'no-such-server'" <<< "$OUT" \
   && grep -q "marksman" <<< "$OUT" && [ ! -s "$MARKER" ]; then
    pass_fail true "an unknown name fails and lists the servers"
else
    pass_fail false "an unknown name fails and lists the servers" "rc=$RC out=$OUT"
fi

# 5. --list names every setup it can find.
RC=0
OUT=$(run_install --list) || RC=$?
if [ "$RC" -eq 0 ] && grep -q "Servers:.*clangd.*marksman.*pylsp.*taplo" <<< "$OUT"; then
    pass_fail true "--list names the installable servers"
else
    pass_fail false "--list names the installable servers" "rc=$RC out=$OUT"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
