#!/usr/bin/env bash
# 096 — downloads stage their temp files under $TMPDIR, not a hard-coded /tmp.
#       /tmp is made unwritable for the test user; with TMPDIR pointing
#       elsewhere the install must still succeed.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
mkdir -p "$HOME/tmp"
sudo chmod 1755 /tmp
sudo chown root:root /tmp
echo "=== TMP LOCKED ==="
touch /tmp/probe 2>/dev/null && echo "tmp=writable" || echo "tmp=locked"
echo "=== INSTALL ==="
TMPDIR="$HOME/tmp" ./booth install 2>&1
echo "exit=$?"
echo "=== LEFTOVERS ==="
ls -A "$HOME/tmp"
echo "(end)"
BASH
)

locked="${LAST_OUTPUT#*=== TMP LOCKED ===}"; locked="${locked%%=== INSTALL*}"
# Without a locked /tmp the test cannot tell the two paths apart.
assert_contains "$locked" "tmp=locked"

install="${LAST_OUTPUT#*=== INSTALL ===}"; install="${install%%=== LEFTOVERS*}"
assert_contains "$install" "CodingBooth installed"
assert_contains "$install" "exit=0"

# Both temp files are moved or removed — nothing left behind in TMPDIR.
leftovers="${LAST_OUTPUT##*=== LEFTOVERS ===}"
assert_eq "$(echo "$leftovers" | tr -d '[:space:]')" "(end)"
pass
