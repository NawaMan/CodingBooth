#!/usr/bin/env bash
# 035 — rc file already contains a stale `# booth function v5` line. Running
#       shell-config should detect the outdated marker, remove it, and inject
#       the current (v6) line. This is the whole point of the bump mechanism.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
# Wipe other rc files so only ~/.bashrc participates.
rm -f ~/.zshrc ~/.bash_profile ~/.profile
cat > ~/.bashrc <<'RC'
# user content above
unalias booth 2>/dev/null; booth() { local d=$PWD; while [[ $d ]]; do [[ -x $d/booth ]] && { "$d/booth" "$@"; return; }; d=${d%/*}; done; echo "STALE" >&2; return 127; } # booth function v5
# user content below
RC

count() { local v; v=$(grep -cE "$1" "$2" 2>/dev/null) || v=0; echo "$v"; }

echo "=== BEFORE ==="
echo "V5: $(count '# booth function v5' ~/.bashrc)"
echo "V6: $(count '# booth function v6' ~/.bashrc)"

./booth shell-config 2>&1
echo "=== AFTER ==="
echo "V5: $(count '# booth function v5' ~/.bashrc)"
echo "V6: $(count '# booth function v6' ~/.bashrc)"
echo "USER_LINES: $(count 'user content' ~/.bashrc)"
BASH
)

before="${LAST_OUTPUT#*=== BEFORE ===}"; before="${before%%./booth shell-config*}"
after="${LAST_OUTPUT##*=== AFTER ===}"

# Before: only v5.
assert_contains "$before" "V5: 1"
assert_contains "$before" "V6: 0"

# After: v5 gone, v6 present, surrounding content kept.
assert_contains "$after" "V5: 0"
assert_contains "$after" "V6: 1"
assert_contains "$after" "USER_LINES: 2"
pass
