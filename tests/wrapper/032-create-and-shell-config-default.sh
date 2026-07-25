#!/usr/bin/env bash
# 032 — shell-config with no subcommand == install; booth create <dir> installs there.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail

export HOME=/tmp/home-create
rm -rf "$HOME"
mkdir -p "$HOME" /work
cp /booth/booth /work/booth
chmod +x /work/booth
cd /work

# --- shell-config (no args) == install ---
./booth shell-config 2>&1
[[ -x "$HOME/.local/share/codingbooth/booth" ]] || { echo "FAIL: central missing after bare shell-config"; exit 1; }
grep -q 'codingbooth shell-config begin' "$HOME/.bashrc" || { echo "FAIL: no bashrc block"; exit 1; }

# --- create <dir> ---
./booth create myapp 2>&1
[[ -x /work/myapp/booth ]] || { echo "FAIL: no myapp/booth"; exit 1; }
[[ -f /work/myapp/.booth/tools/codingbooth.lock ]] || { echo "FAIL: no lock in myapp"; exit 1; }

# create with nested path
./booth create nest/deep 2>&1
[[ -x /work/nest/deep/booth ]] || { echo "FAIL: nested booth missing"; exit 1; }

echo "create-and-shell-config-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "create-and-shell-config-ok"
assert_contains "$LAST_OUTPUT" "✓ Central wrapper:"
assert_contains "$LAST_OUTPUT" "✓ Project wrapper:"
assert_contains "$LAST_OUTPUT" "CodingBooth installed"
pass
