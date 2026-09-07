#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Argument handling and failure branches of mojo--setup.sh, with apt-get and
# pip stubbed. A real pip install of Mojo belongs in the complex boothfile test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOJO_SCRIPT="$REPO_ROOT/variants/base/setups/mojo--setup.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/empty" "$STUB/opt/python/bin" "$STUB/bindir"

cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/apt-get"

cat > "$STUB/bin/g++" << 'EOF'
#!/bin/bash
echo "STUB_GXX $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/g++"

# The setup cleans /var/lib/apt/lists after apt-get; that path is not ours to
# touch on the host. Stub rm so the cleanup is a logged no-op.
cat > "$STUB/bin/rm" << 'EOF'
#!/bin/bash
echo "STUB_RM $*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$STUB/bin/rm"

# Fake CPython at CB_PYTHON_HOME: version probe + `python -m pip`.
cat > "$STUB/opt/python/bin/python" << 'EOF'
#!/bin/bash
echo "STUB_PYTHON $*" >> "$STUB_LOG"
if [[ "${1:-}" == "-c" ]]; then
    if [[ "${2:-}" == *"SystemExit"* ]]; then
        [[ "${STUB_PY_RANGE:-ok}" == "ok" ]] && exit 0
        exit 1
    fi
    if [[ "${2:-}" == *"join"* ]]; then
        echo "${STUB_PY_VER:-3.9.0}"
        exit 0
    fi
    exit 0
fi
if [[ "${1:-}" == "-m" && "${2:-}" == "pip" ]]; then
    shift 2
    echo "STUB_PIP $*" >> "$STUB_LOG"
    cat > "$(dirname "$0")/mojo" <<'M'
#!/bin/sh
echo "mojo 1.0.0"
M
    chmod +x "$(dirname "$0")/mojo"
    exit 0
fi
exit 0
EOF
chmod +x "$STUB/opt/python/bin/python"

run_mojo_setup() {
    local extra_env="$1"; shift
    : > "$STUB/log"
    # shellcheck disable=SC2086
    env $extra_env \
        PATH="$STUB/bin:/usr/bin:/bin" \
        STUB_LOG="$STUB/log" \
        CB_PYTHON_HOME="$STUB/opt/python" \
        CB_MOJO_BIN_DIR="$STUB/bindir" \
        SETUP_LIBS_DIR="$REPO_ROOT/variants/base/setups/libs" \
        EUID=0 \
        bash "$MOJO_SCRIPT" "$@" 2>&1
}

ALL_PASSED=true

# 1. Default pin pip-installs mojo==1.0.0 and links the binary.
out=$(run_mojo_setup "") && rc=0 || rc=$?
if [[ $rc -eq 0 ]] \
    && grep -q "STUB_PIP install mojo==1.0.0" "$STUB/log" \
    && grep -q "STUB_APT install" "$STUB/log" \
    && [[ -L "$STUB/bindir/mojo" ]]; then
    print_test_result "true" "$0" "1" "default installs mojo==1.0.0 and links the binary"
else
    print_test_result "false" "$0" "1" "default installs mojo==1.0.0 and links the binary"
    echo "  rc=$rc"
    echo "  stub log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

# 2. --version latest is an unpinned upgrade.
out=$(run_mojo_setup "" --version latest) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "STUB_PIP install --upgrade mojo" "$STUB/log"; then
    print_test_result "true" "$0" "2" "--version latest pip-installs unpinned mojo"
else
    print_test_result "false" "$0" "2" "--version latest pip-installs unpinned mojo"
    echo "  rc=$rc"
    echo "  stub log:"; cat "$STUB/log" | sed 's/^/    /'
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

# 3. Missing Python is a hard error, not a skip.
rm -f "$STUB/opt/python/bin/python"
out=$(run_mojo_setup "") && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "Python is not set up"; then
    print_test_result "true" "$0" "3" "missing python fails the build"
else
    print_test_result "false" "$0" "3" "missing python fails the build"
    echo "  rc=$rc (want non-zero)"
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi
# Restore the fake interpreter for later cases.
chmod +x "$STUB/opt/python/bin/python" 2>/dev/null || true
# The rm removed it — rewrite.
cat > "$STUB/opt/python/bin/python" << 'EOF'
#!/bin/bash
echo "STUB_PYTHON $*" >> "$STUB_LOG"
if [[ "${1:-}" == "-c" ]]; then
    if [[ "${2:-}" == *"SystemExit"* ]]; then
        [[ "${STUB_PY_RANGE:-ok}" == "ok" ]] && exit 0
        exit 1
    fi
    if [[ "${2:-}" == *"join"* ]]; then
        echo "${STUB_PY_VER:-3.9.0}"
        exit 0
    fi
    exit 0
fi
if [[ "${1:-}" == "-m" && "${2:-}" == "pip" ]]; then
    shift 2
    echo "STUB_PIP $*" >> "$STUB_LOG"
    cat > "$(dirname "$0")/mojo" <<'M'
#!/bin/sh
echo "mojo 1.0.0"
M
    chmod +x "$(dirname "$0")/mojo"
    exit 0
fi
exit 0
EOF
chmod +x "$STUB/opt/python/bin/python"

# 4. Python outside 3.10–3.14 fails with the found version.
out=$(run_mojo_setup "STUB_PY_RANGE=bad STUB_PY_VER=3.9.18") && rc=0 || rc=$?
if [[ $rc -ne 0 ]] \
    && echo "$out" | grep -q "Python 3.10–3.14" \
    && echo "$out" | grep -q "3.9.18"; then
    print_test_result "true" "$0" "4" "too-old python fails with the found version"
else
    print_test_result "false" "$0" "4" "too-old python fails with the found version"
    echo "  rc=$rc (want non-zero)"
    echo "  output:"; echo "$out" | sed 's/^/    /'
    ALL_PASSED=false
fi

# 5. Unknown flag is a usage error (exit 2), not a pip install.
out=$(run_mojo_setup "" --nope) && rc=0 || rc=$?
if [[ $rc -eq 2 ]] \
    && echo "$out" | grep -q "Unknown arg" \
    && ! grep -q "STUB_PIP" "$STUB/log"; then
    print_test_result "true" "$0" "5" "unknown arg exits 2 without pip"
else
    print_test_result "false" "$0" "5" "unknown arg exits 2 without pip"
    echo "  rc=$rc (want 2)"
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
