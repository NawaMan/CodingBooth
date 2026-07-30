#!/usr/bin/env bash
# 052 — `booth config` without an install offers to install (TTY only) and
#       continues; non-TTY keeps the hard error. Other commands never prompt.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail

cp /booth/booth ./booth
chmod +x ./booth

# --- non-TTY: config refuses without silent install ---
echo "=== NON-TTY CONFIG ==="
set +e
./booth config --help > /tmp/cfg-out.txt 2>&1
cfg_rc=$?
set -e
cat /tmp/cfg-out.txt
echo "rc=$cfg_rc"
[[ "$cfg_rc" -ne 0 ]] || { echo "FAIL: non-TTY config should fail"; exit 1; }
grep -q 'CodingBooth is not installed' /tmp/cfg-out.txt || { echo "FAIL: missing not-installed"; exit 1; }
grep -q 'Please run:.*install' /tmp/cfg-out.txt || { echo "FAIL: missing install hint"; exit 1; }
# Must not have downloaded / written a lock
if [[ -f .booth/tools/codingbooth.lock ]]; then
    echo "FAIL: non-TTY config wrote a lock file"
    exit 1
fi

# --- non-TTY: list still hard-errors (no config-only wording) ---
echo "=== NON-TTY LIST ==="
set +e
./booth list > /tmp/list-out.txt 2>&1
list_rc=$?
set -e
cat /tmp/list-out.txt
echo "rc=$list_rc"
[[ "$list_rc" -ne 0 ]] || { echo "FAIL: non-TTY list should fail"; exit 1; }
grep -q 'CodingBooth is not installed' /tmp/list-out.txt || { echo "FAIL: list missing not-installed"; exit 1; }
grep -q 'Install and continue' /tmp/list-out.txt && { echo "FAIL: list must not offer install"; exit 1; }

# --- TTY decline: cancel, no lock ---
echo "=== TTY DECLINE ==="
# script allocates a PTY so OfferInstallForConfig sees -t 0; feed "n".
set +e
script -q -e -c "./booth config --help" /tmp/script-decline.log <<'EOF' > /tmp/decline-out.txt 2>&1
n
EOF
decline_rc=$?
set -e
cat /tmp/decline-out.txt
# also show typescript if useful
[[ -f /tmp/script-decline.log ]] && cat /tmp/script-decline.log || true
echo "rc=$decline_rc"
grep -q 'Cancelled' /tmp/decline-out.txt /tmp/script-decline.log 2>/dev/null \
    || grep -q 'Cancelled' /tmp/decline-out.txt \
    || { echo "FAIL: decline should say Cancelled"; exit 1; }
if [[ -f .booth/tools/codingbooth.lock ]]; then
    echo "FAIL: decline wrote a lock file"
    exit 1
fi

# --- TTY accept: install then run config --help via the binary ---
echo "=== TTY ACCEPT ==="
set +e
script -q -e -c "./booth config --help" /tmp/script-accept.log <<'EOF' > /tmp/accept-out.txt 2>&1
y
EOF
accept_rc=$?
set -e
cat /tmp/accept-out.txt
[[ -f /tmp/script-accept.log ]] && cat /tmp/script-accept.log || true
echo "rc=$accept_rc"
[[ -f .booth/tools/codingbooth.lock ]] || { echo "FAIL: accept did not write lock"; exit 1; }
# Combined output (stdout capture + typescript) should show install + config help
combined="$(cat /tmp/accept-out.txt /tmp/script-accept.log 2>/dev/null || true)"
echo "$combined" | grep -q 'CodingBooth installed' \
    || echo "$combined" | grep -q 'already up-to-date' \
    || { echo "FAIL: accept did not install"; exit 1; }
# Binary config help (after install + continue)
echo "$combined" | grep -qi 'config' \
    || { echo "FAIL: config help not shown after install"; exit 1; }
[[ "$accept_rc" -eq 0 ]] || { echo "FAIL: accept path should exit 0"; exit 1; }

# --- central wrapper: accept installs into $PWD, not next to central ---
echo "=== CENTRAL ACCEPT ==="
export HOME=/tmp/home-config-offer
rm -rf "$HOME"
mkdir -p "$HOME/proj"
cp /booth/booth /tmp/seed-booth
chmod +x /tmp/seed-booth
/tmp/seed-booth shell-config install >/dev/null
central="$HOME/.local/share/codingbooth/booth"
[[ -x "$central" ]]
cd "$HOME/proj"
set +e
script -q -e -c "$central config --help" /tmp/script-central.log <<'EOF' > /tmp/central-out.txt 2>&1
y
EOF
central_rc=$?
set -e
cat /tmp/central-out.txt
[[ -f /tmp/script-central.log ]] && cat /tmp/script-central.log || true
echo "rc=$central_rc"
[[ -x "$HOME/proj/booth" ]] || { echo "FAIL: central accept did not create project booth"; exit 1; }
[[ -f "$HOME/proj/.booth/tools/codingbooth.lock" ]] || { echo "FAIL: no lock in project"; exit 1; }
if [[ -f "$HOME/.local/share/codingbooth/.booth/tools/codingbooth.lock" ]]; then
    echo "FAIL: lock written next to central wrapper"
    exit 1
fi
[[ "$central_rc" -eq 0 ]] || { echo "FAIL: central accept should exit 0"; exit 1; }

# --- foreign wrapper that already has a lock (the user bug): still offer ---
# Simulate `../CodingBooth/booth config` from an empty NewBooth directory.
echo "=== FOREIGN WRAPPER OFFER ==="
export HOME=/tmp/home-foreign-offer
rm -rf "$HOME"
mkdir -p "$HOME/codingbooth" "$HOME/newbooth"
cp /booth/booth "$HOME/codingbooth/booth"
chmod +x "$HOME/codingbooth/booth"
# Give the foreign tree a real install so its LOCK_FILE exists
cd "$HOME/codingbooth"
./booth install >/dev/null
[[ -f "$HOME/codingbooth/.booth/tools/codingbooth.lock" ]]

cd "$HOME/newbooth"
set +e
script -q -e -c "$HOME/codingbooth/booth config --help" /tmp/script-foreign.log <<'EOF' > /tmp/foreign-out.txt 2>&1
y
EOF
foreign_rc=$?
set -e
cat /tmp/foreign-out.txt
[[ -f /tmp/script-foreign.log ]] && cat /tmp/script-foreign.log || true
echo "rc=$foreign_rc"
combined_f="$(cat /tmp/foreign-out.txt /tmp/script-foreign.log 2>/dev/null || true)"
echo "$combined_f" | grep -q 'Install and continue' \
    || echo "$combined_f" | grep -q 'not installed in this project' \
    || { echo "FAIL: foreign wrapper must offer install for empty project"; exit 1; }
[[ -x "$HOME/newbooth/booth" ]] || { echo "FAIL: no booth in newbooth"; exit 1; }
[[ -f "$HOME/newbooth/.booth/tools/codingbooth.lock" ]] || { echo "FAIL: no lock in newbooth"; exit 1; }
[[ "$foreign_rc" -eq 0 ]] || { echo "FAIL: foreign accept should exit 0"; exit 1; }

# --- orphan lock in a parent (e.g. ~/.booth without ./booth) must not suppress ---
echo "=== ORPHAN PARENT LOCK ==="
export HOME=/tmp/home-orphan-lock
rm -rf "$HOME"
# Stale lock under home, no booth wrapper (reproduces real user home layout)
mkdir -p "$HOME/.booth/tools" "$HOME/newbooth" "$HOME/tooling"
printf 'version=0.25.0\ndownloaded_at=2026-01-01T00:00:00Z\ncache=shared\n' \
    > "$HOME/.booth/tools/codingbooth.lock"
cp /booth/booth "$HOME/tooling/booth"
chmod +x "$HOME/tooling/booth"
cd "$HOME/tooling"
./booth install >/dev/null
cd "$HOME/newbooth"
set +e
script -q -e -c "$HOME/tooling/booth config --help" /tmp/script-orphan.log <<'EOF' > /tmp/orphan-out.txt 2>&1
y
EOF
orphan_rc=$?
set -e
cat /tmp/orphan-out.txt
[[ -f /tmp/script-orphan.log ]] && cat /tmp/script-orphan.log || true
echo "rc=$orphan_rc"
combined_o="$(cat /tmp/orphan-out.txt /tmp/script-orphan.log 2>/dev/null || true)"
echo "$combined_o" | grep -q 'not installed in this project' \
    || echo "$combined_o" | grep -q 'Install and continue' \
    || { echo "FAIL: orphan parent lock must not suppress offer"; exit 1; }
[[ -f "$HOME/newbooth/.booth/tools/codingbooth.lock" ]] \
    || { echo "FAIL: newbooth should get a lock after accept"; exit 1; }
[[ "$orphan_rc" -eq 0 ]] || { echo "FAIL: orphan-parent accept should exit 0"; exit 1; }

echo "config-offer-install-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "config-offer-install-ok"
assert_contains "$LAST_OUTPUT" "=== NON-TTY CONFIG ==="
assert_contains "$LAST_OUTPUT" "=== TTY ACCEPT ==="
assert_contains "$LAST_OUTPUT" "=== CENTRAL ACCEPT ==="
assert_contains "$LAST_OUTPUT" "=== FOREIGN WRAPPER OFFER ==="
pass
