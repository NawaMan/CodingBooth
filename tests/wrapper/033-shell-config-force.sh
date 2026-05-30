#!/usr/bin/env bash
# 033 — shell-config sees a custom booth() (no booth-managed marker) and
#       skips without --force; with --force it overwrites.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
# Wipe other rc files so only ~/.bashrc participates.
rm -f ~/.zshrc ~/.bash_profile ~/.profile
cat > ~/.bashrc <<'RC'
# user content above
booth() { echo "my custom booth"; }
# user content below
RC

count() { local v; v=$(grep -cE "$1" "$2" 2>/dev/null) || v=0; echo "$v"; }

echo "=== WITHOUT --force ==="
./booth shell-config 2>&1
echo "MARKERS: $(count '# booth function v[0-9]+' ~/.bashrc)"
echo "CUSTOM: $(count 'my custom booth' ~/.bashrc)"

echo "=== WITH --force ==="
./booth shell-config --force 2>&1
echo "MARKERS: $(count '# booth function v6' ~/.bashrc)"
echo "CUSTOM: $(count 'my custom booth' ~/.bashrc)"
BASH
)

without="${LAST_OUTPUT#*=== WITHOUT --force ===}"; without="${without%%=== WITH --force*}"
withf="${LAST_OUTPUT##*=== WITH --force ===}"

# Without --force: custom detected, no marker added, custom preserved.
assert_contains "$without" "Custom booth() detected"
assert_contains "$without" "MARKERS: 0"
assert_contains "$without" "CUSTOM: 1"

# With --force: marker line appended so the booth wrapper function takes
# precedence. The custom function text remains in the file (bash's last
# definition wins at source time — we don't try to surgically remove the
# user's code).
assert_contains "$withf" "Force-installed booth function"
assert_contains "$withf" "MARKERS: 1"
assert_contains "$withf" "CUSTOM: 1"
pass
