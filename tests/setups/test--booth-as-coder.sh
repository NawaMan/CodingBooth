#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: booth--as-coder, the helper booth-entry (and, in an
# --apple-low-ports booth, shell/exec) starts coder's processes through.
#
# Without the /run/booth-low-ports marker it must be exactly the runuser call
# booth-entry used to make, so Docker and Podman booths are unchanged. With
# the marker it switches user with setpriv and hands coder NET_BIND_SERVICE as
# an ambient capability (runuser would drop it), keeping the environment the
# way runuser does — and, for --login, building the clean login environment.
#
# The helper runs as root against real accounts, so here it runs on a copy
# with the marker path pointed at a throwaway file and id/getent/runuser/
# setpriv stubbed to print what they were asked to do. The real path is not
# made overridable on purpose: inside a booth nothing should be able to point
# the helper at a marker of its own. No root, no container needed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER_SRC="$REPO_ROOT/variants/base/booth--as-coder"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

MARKER="$WORK/booth-low-ports"
HELPER="$WORK/booth--as-coder"
sed "s|^LOW_PORTS_MARKER=\"/run/booth-low-ports\"$|LOW_PORTS_MARKER=\"$MARKER\"|" "$HELPER_SRC" > "$HELPER"
chmod +x "$HELPER"
if ! grep -q "^LOW_PORTS_MARKER=\"$MARKER\"$" "$HELPER"; then
    echo "❌ Could not point the helper at a test marker (its LOW_PORTS_MARKER line may have changed)"
    exit 1
fi

# Stubs: root by default (FAKE_UID), coder's passwd entry (home in $WORK, as
# --login changes into it), and runuser/setpriv
# that print their arguments instead of switching user.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/id" <<'EOF'
#!/bin/sh
echo "${FAKE_UID:-0}"
EOF
mkdir -p "$WORK/home"
cat > "$WORK/bin/getent" <<EOF
#!/bin/sh
[ "\$1 \$2" = "passwd coder" ] && echo "coder:x:501:20:coder:$WORK/home:/bin/bash"
EOF
cat > "$WORK/bin/runuser" <<'EOF'
#!/bin/sh
echo "runuser $*"
EOF
cat > "$WORK/bin/setpriv" <<'EOF'
#!/bin/sh
echo "setpriv $*"
EOF
chmod +x "$WORK/bin/"*

run_helper() {
    PATH="$WORK/bin:/usr/bin:/bin" HOME=/root "$HELPER" "$@" 2>&1
}

TEST_NUM=0
ALL_PASSED=true

check() { # desc expected actual
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$3" == "$2" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$1"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$1"
        echo "   expected: $2"
        echo "   actual:   $3"
        ALL_PASSED=false
    fi
}

check_has() { # desc needle actual
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$3" == *"$2"* ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$1"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$1 (missing: '$2')"
        echo "   actual: $3"
        ALL_PASSED=false
    fi
}

# 1-2. No marker: exactly the runuser calls booth-entry made before.
rm -f "$MARKER"
check "no marker: runs the command through runuser, as before" \
    "runuser -u coder -- echo hi" "$(run_helper -- echo hi)"
check "no marker: --login is runuser --login, as before" \
    "runuser -u coder --login" "$(run_helper --login)"

# 3-6. Marker: setpriv to coder with NET_BIND_SERVICE handed down.
: > "$MARKER"
OUT="$(run_helper -- echo hi)"
check_has "marker: switches to coder's uid/gid with setpriv" "setpriv --reuid=501 --regid=20 --init-groups" "$OUT"
check_has "marker: hands down NET_BIND_SERVICE as an ambient capability" \
    "--inh-caps=+net_bind_service --ambient-caps=+net_bind_service" "$OUT"
check_has "marker: sets coder's HOME/SHELL/USER/LOGNAME, then runs the command" \
    "env HOME=$WORK/home SHELL=/bin/bash USER=coder LOGNAME=coder echo hi" "$OUT"
check_has "marker: --login starts a clean login shell" \
    "env -i TERM=" "$(run_helper --login)"

# 7. Not root: nothing to switch, the command just runs.
check "not root: runs the command as is" "hi" "$(FAKE_UID=1000 run_helper -- echo hi)"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
