#!/usr/bin/env bash
# 016 — modifying the cached binary should make the wrapper refuse to run
#       it ("failed SHA256 verification").
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
bin=$(find ~/.cache/codingbooth/versions -name 'codingbooth-*' -type f | head -1)
[[ -n "$bin" ]] || { echo "ERROR: binary not found in shared cache"; exit 99; }
chmod +w "$bin"
printf 'tampered\n' >> "$bin"
echo "=== AFTER TAMPER ==="
./booth list 2>&1 || true
BASH
)

after="${LAST_OUTPUT##*=== AFTER TAMPER ===}"
assert_contains "$after" "failed SHA256 verification"
pass
