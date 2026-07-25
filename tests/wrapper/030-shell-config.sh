#!/usr/bin/env bash
# 030 — shell-config install/uninstall is idempotent; walk-up + central fallback.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail

export HOME=/tmp/home-shell-config
rm -rf "$HOME"
mkdir -p "$HOME"

cp /booth/booth ./booth
chmod +x ./booth

# --- install ---
./booth shell-config install

central="$HOME/.local/share/codingbooth/booth"
[[ -x "$central" ]] || { echo "FAIL: central missing"; exit 1; }
grep -qxF '# >>> codingbooth shell-config begin >>>' "$HOME/.bashrc"
grep -qxF '# <<< codingbooth shell-config end <<<' "$HOME/.bashrc"
grep -qxF '# >>> codingbooth shell-config begin >>>' "$HOME/.zshrc"
grep -qxF '# >>> codingbooth shell-config begin >>>' "$HOME/.config/fish/functions/booth.fish"
grep -q "function booth" "$HOME/.config/fish/functions/booth.fish"

# --- idempotent: second install keeps a single block ---
./booth shell-config install
begin_count=$(grep -c 'codingbooth shell-config begin' "$HOME/.bashrc" || true)
[[ "$begin_count" == "1" ]] || { echo "FAIL: expected 1 begin marker, got $begin_count"; exit 1; }

# Preserve user content around the block
echo "# user line after" >> "$HOME/.bashrc"
./booth shell-config install
grep -q '# user line after' "$HOME/.bashrc" || { echo "FAIL: lost user content"; exit 1; }
begin_count=$(grep -c 'codingbooth shell-config begin' "$HOME/.bashrc" || true)
[[ "$begin_count" == "1" ]] || { echo "FAIL: markers after third install: $begin_count"; exit 1; }

# --- status ---
status_out=$(./booth shell-config status)
echo "$status_out" | grep -q 'status: present'
echo "$status_out" | grep -q '\[installed\].*\.bashrc'

# --- walk-up: project booth from subdirectory ---
mkdir -p "$HOME/proj/deep"
cp ./booth "$HOME/proj/booth"
chmod +x "$HOME/proj/booth"
# shellcheck disable=SC1090
source "$HOME/.bashrc"
cd "$HOME/proj/deep"
# booth version should hit project wrapper (prints "CodingBooth Wrapper")
out=$(booth version 2>&1) || true
echo "$out" | grep -q 'CodingBooth Wrapper' || { echo "FAIL: walk-up version: $out"; exit 1; }

# --- central fallback: no project booth above cwd ---
cd /tmp
out=$(booth help 2>&1) || true
echo "$out" | grep -q 'Wrapper commands:' || { echo "FAIL: central help: $out"; exit 1; }

# --- uninstall ---
cd /work
./booth shell-config uninstall
[[ ! -e "$central" ]] || { echo "FAIL: central still present"; exit 1; }
if grep -q 'codingbooth shell-config begin' "$HOME/.bashrc" 2>/dev/null; then
    echo "FAIL: begin marker still in bashrc"
    exit 1
fi
grep -q '# user line after' "$HOME/.bashrc" || { echo "FAIL: user line removed on uninstall"; exit 1; }

# uninstall again is idempotent
./booth shell-config uninstall

echo "shell-config-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "shell-config-ok"
assert_contains "$LAST_OUTPUT" "✓ Central wrapper:"
assert_contains "$LAST_OUTPUT" "✓ bash:"
assert_contains "$LAST_OUTPUT" "✓ fish:"
pass
