#!/usr/bin/env bash
# 021 — uninstall --shell-config -y removes the booth() one-liner from
#       ~/.bashrc and leaves a backup file.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
cat > ~/.bashrc <<'RC'
# leading user content
export PATH=/foo:$PATH
RC

# count: safe `grep -c` wrapper that prints 0 instead of erroring on no-match.
count() { local v; v=$(grep -cE "$1" "$2" 2>/dev/null) || v=0; echo "$v"; }

./booth shell-config >/dev/null
echo "=== BEFORE UNINSTALL ==="
echo "MARKERS: $(count '# booth function v[0-9]+' ~/.bashrc)"

echo "=== RUN UNINSTALL ==="
./booth uninstall --shell-config -y
echo "=== AFTER UNINSTALL ==="
echo "MARKERS: $(count '# booth function v[0-9]+' ~/.bashrc)"
echo "BACKUP EXISTS: $([[ -f ~/.bashrc.booth-bak ]] && echo yes || echo no)"
echo "USER CONTENT KEPT: $(count 'export PATH=/foo' ~/.bashrc)"
BASH
)

before="${LAST_OUTPUT#*=== BEFORE UNINSTALL ===}"; before="${before%%=== RUN UNINSTALL*}"
after="${LAST_OUTPUT##*=== AFTER UNINSTALL ===}"

assert_contains "$before" "MARKERS: 1"
assert_contains "$after" "MARKERS: 0"
assert_contains "$LAST_OUTPUT" "Removed booth function from"
assert_contains "$after" "BACKUP EXISTS: yes"
assert_contains "$after" "USER CONTENT KEPT: 1"
pass
