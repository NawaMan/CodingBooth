#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# lazarus--setup.sh always installs the headless toolchain (lazbuild + LCL + the gtk2 link
# libs) and adds the IDE, its first-run prerequisites and a desktop icon only on a desktop.
# "latest" resolves to the series the `lazarus` meta-package points at.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/lazarus--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin"

cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT $*" >> "$STUB_LOG"
EOF

# `policy lazarus` reports the candidate; `show <pkg>` succeeds only for the 4.4 series.
cat > "$STUB/bin/apt-cache" << 'EOF'
#!/bin/bash
case "$1" in
  policy) printf 'lazarus:\n  Installed: (none)\n  Candidate: 4.4+dfsg-4\n' ;;
  show)   [[ "$2" == *-4.4 ]] ;;
esac
EOF

cat > "$STUB/bin/cb-has-desktop.sh" << 'EOF'
#!/bin/bash
[[ "$STUB_DESKTOP" == 1 ]]
EOF

cat > "$STUB/bin/cb-desktop-icon.sh" << 'EOF'
#!/bin/bash
echo "STUB_ICON $*" >> "$STUB_LOG"
EOF

cat > "$STUB/bin/lazbuild" << 'EOF'
#!/bin/bash
echo "STUB_LAZBUILD $*" >> "$STUB_LOG"
[[ "${STUB_LAZBUILD_FAIL:-0}" == 1 ]] && exit 1
exit 0
EOF

# The script clears /var/lib/apt/lists — never let it touch the host's.
cat > "$STUB/bin/rm" << 'EOF'
#!/bin/bash
echo "STUB_RM $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/"*

run_setup() {
    local desktop="$1"; shift
    : > "$STUB/log"
    PATH="$STUB/bin:/usr/bin:/bin" STUB_LOG="$STUB/log" STUB_DESKTOP="$desktop" \
        /usr/bin/env EUID=0 bash "$SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

check() {
    local num="$1" name="$2"; shift 2
    if "$@"; then
        print_test_result "true" "$0" "$num" "$name"
    else
        print_test_result "false" "$0" "$num" "$name"
        echo "  rc=$rc"; echo "  log:"; sed 's/^/    /' "$STUB/log"
        echo "  out:"; echo "$out" | sed 's/^/    /'
        ALL_PASSED=false
    fi
}

install_line() { grep '^STUB_APT install' "$STUB/log"; }

# 1. No desktop: headless toolchain only, built once, no IDE, no icon.
out=$(run_setup 0) && rc=0 || rc=$?
check 1 "no desktop: lazbuild + LCL for the latest series, no IDE, no icon" bash -c '
    [[ '"$rc"' -eq 0 ]] || exit 1
    line=$(grep "^STUB_APT install" "'"$STUB/log"'")
    for p in fpc lcl-utils-4.4 lcl-units-4.4 lcl-gtk2-4.4 lazarus-src-4.4 libgtk2.0-dev; do
        [[ " $line " == *" $p "* ]] || exit 1
    done
    [[ "$line" != *lazarus-ide* && "$line" != *fpc-source* ]] || exit 1
    grep -q "^STUB_LAZBUILD .*warm.lpi" "'"$STUB/log"'" || exit 1
    ! grep -q "^STUB_ICON" "'"$STUB/log"'"'

# 2. Desktop: the IDE, its first-run prerequisites, and the icon.
out=$(run_setup 1) && rc=0 || rc=$?
check 2 "desktop: IDE + fpc-source + make, and a desktop icon" bash -c '
    [[ '"$rc"' -eq 0 ]] || exit 1
    line=$(grep "^STUB_APT install" "'"$STUB/log"'")
    for p in lcl-utils-4.4 lazarus-ide-4.4 lazarus-ide-gtk2-4.4 lazarus-4.4 fpc-source make; do
        [[ " $line " == *" $p "* ]] || exit 1
    done
    grep -q "^STUB_ICON lazarus$" "'"$STUB/log"'"'

# 3. A pinned series apt does not have fails loudly instead of installing something else.
out=$(run_setup 0 --version 9.9) && rc=0 || rc=$?
check 3 "--version 9.9 (unavailable) fails without installing" bash -c '
    [[ '"$rc"' -ne 0 ]] || exit 1
    echo "$0" | grep -q "Lazarus 9.9 is not available" || exit 1
    ! grep -q "^STUB_APT install" "'"$STUB/log"'"' "$out"

# 4. If lazbuild cannot build an LCL program, the setup fails the build.
out=$(STUB_LAZBUILD_FAIL=1 run_setup 0) && rc=0 || rc=$?
check 4 "a failing lazbuild fails the setup" bash -c '
    [[ '"$rc"' -ne 0 ]] && echo "$0" | grep -q "lazbuild could not build"' "$out"

if [[ "$ALL_PASSED" == true ]]; then
    echo "✅ All tests passed"
    exit 0
fi
echo "❌ Some tests failed"
exit 1
