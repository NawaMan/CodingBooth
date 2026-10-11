#!/usr/bin/env bash
# 033 — a wrapper on PATH with no lock beside it (Homebrew's) hands off to the
# project's ./booth from the project root and from a subfolder, with no shell
# function; shell-config and uninstall leave Homebrew's file alone.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH' || true
set -euo pipefail

export HOME=/tmp/home-brew
rm -rf "$HOME"
mkdir -p "$HOME"

# Homebrew layout: the file lives in the Cellar, bin/ holds a symlink to it.
prefix=/tmp/brew
mkdir -p "$prefix/Cellar/codingbooth/1.0.0/bin" "$prefix/bin"
cp /booth/booth "$prefix/Cellar/codingbooth/1.0.0/bin/booth"
chmod 755 "$prefix/Cellar/codingbooth/1.0.0/bin/booth"
ln -s ../Cellar/codingbooth/1.0.0/bin/booth "$prefix/bin/booth"
export PATH="$prefix/bin:$PATH"
[[ "$(command -v booth)" == "$prefix/bin/booth" ]] || { echo "FAIL: booth not on PATH"; exit 1; }

# --- install from the brewed booth lands in $PWD ---
mkdir -p "$HOME/proj/src/deep"
cd "$HOME/proj"
booth install 2>&1
[[ -f "$HOME/proj/.booth/tools/codingbooth.lock" ]] || { echo "FAIL: no lock in project"; exit 1; }

# --- version reaches the project's wrapper (root and subfolder) ---
out=$(booth version 2>&1)
echo "$out" | grep -q 'Cache mode: shared' || { echo "FAIL: root version: $out"; exit 1; }
cd "$HOME/proj/src/deep"
out=$(booth version 2>&1)
echo "$out" | grep -q 'Cache mode: shared' || { echo "FAIL: subfolder version: $out"; exit 1; }

# --- a command without --code runs from the project root ---
out=$(booth config --no-tui --dryrun 2>&1) || true
echo "$out" | grep -q '=== config.toml ===' || { echo "FAIL: subfolder config: $out"; exit 1; }

# --- a command with --code gets the project root as --code ---
out=$(booth emit-dockerfile 2>&1) || true
echo "$out" | grep -q "$HOME/proj/.booth/Boothfile" || { echo "FAIL: subfolder emit-dockerfile: $out"; exit 1; }

# --- install/update in a project runs the project's wrapper, never copies over it ---
cd "$HOME/proj"
echo "# project-marker" >> ./booth
booth install 2>&1
grep -q '# project-marker' ./booth || { echo "FAIL: brewed booth overwrote ./booth"; exit 1; }

# --- shell-config refuses: nothing copied, no rc block ---
out=$(booth shell-config install 2>&1)
echo "$out" | grep -q 'managed by Homebrew' || { echo "FAIL: shell-config: $out"; exit 1; }
[[ ! -e "$HOME/.local/share/codingbooth/booth" ]] || { echo "FAIL: central copy made"; exit 1; }
if grep -qs 'codingbooth shell-config begin' "$HOME/.bashrc"; then
    echo "FAIL: rc block written"; exit 1
fi

# --- uninstall outside a project refuses; Homebrew's file stays ---
cd /tmp
out=$(booth uninstall --wrapper -y 2>&1) && { echo "FAIL: uninstall succeeded"; exit 1; }
echo "$out" | grep -q 'brew uninstall codingbooth' || { echo "FAIL: uninstall msg: $out"; exit 1; }
[[ -f "$prefix/Cellar/codingbooth/1.0.0/bin/booth" ]] || { echo "FAIL: Cellar booth deleted"; exit 1; }

# --- lockless project wrappers hand off at most once: no loop ---
mkdir -p "$HOME/loop/inner/x"
cp /booth/booth "$HOME/loop/booth"
cp /booth/booth "$HOME/loop/inner/booth"
cd "$HOME/loop/inner/x"
out=$(timeout 20 booth list 2>&1) && rc=0 || rc=$?
[[ $rc -ne 124 ]] || { echo "FAIL: hand-off loop"; exit 1; }
echo "$out" | grep -q 'not installed' || { echo "FAIL: lockless project: $out"; exit 1; }

echo "global-mode-homebrew-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "global-mode-homebrew-ok"
assert_contains "$LAST_OUTPUT" "CodingBooth installed"
pass
