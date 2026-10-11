#!/usr/bin/env bash
# 034 — through the shell-config function, commands that do not take --code
# work from a project subfolder. The old function appended --code to all of
# them: `config` said "unknown flag: --code", `list` "flag provided but not defined".
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH' || true
set -euo pipefail

export HOME=/tmp/home-shell-subfolder
rm -rf "$HOME"
mkdir -p "$HOME/proj/src/deep"

cp /booth/booth /tmp/seed-booth
chmod +x /tmp/seed-booth
/tmp/seed-booth shell-config install >/dev/null

# The function is now a single call to the central wrapper.
grep -q '"$_cb_central" "$@"' "$HOME/.bashrc" || { echo "FAIL: function body"; exit 1; }

# shellcheck disable=SC1090
source "$HOME/.bashrc"
cd "$HOME/proj"
booth install 2>&1

cd "$HOME/proj/src/deep"
for cmd in "config --no-tui --dryrun" "template list" "list"; do
    # shellcheck disable=SC2086
    out=$(booth $cmd 2>&1) || true
    if echo "$out" | grep -qE 'unknown flag: --code|not defined: -code'; then
        echo "FAIL: '$cmd' got --code: $out"; exit 1
    fi
done

out=$(booth config --no-tui --dryrun 2>&1) || true
echo "$out" | grep -q '=== config.toml ===' || { echo "FAIL: config from subfolder: $out"; exit 1; }

# A run from a subfolder still mounts the project root, and a trailing
# `-- cmd` is left intact (the old function appended --code after it).
out=$(booth --dryrun -- ls 2>&1) || true
echo "$out" | grep -q -- "-v $HOME/proj:/home/coder/code" || { echo "FAIL: run code path: $out"; exit 1; }

echo "shell-function-subfolder-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "shell-function-subfolder-ok"
pass
