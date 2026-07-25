#!/usr/bin/env bash
# 031 — `booth install` always targets $PWD (even if a parent ./booth exists).
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail

export HOME=/tmp/home-install-central
rm -rf "$HOME"
mkdir -p "$HOME"

cp /booth/booth /tmp/seed-booth
chmod +x /tmp/seed-booth

# Parent booth (like docker test layout: /work/booth while cwd is /work/proj)
mkdir -p "$HOME/work/proj"
cp /tmp/seed-booth "$HOME/work/booth"
chmod +x "$HOME/work/booth"

# Central via shell-config
/tmp/seed-booth shell-config install
central="$HOME/.local/share/codingbooth/booth"
[[ -x "$central" ]]

# --- central install into empty project ---
cd "$HOME/work/proj"
"$central" install 2>&1

[[ -x "$HOME/work/proj/booth" ]] || { echo "FAIL: no project booth"; exit 1; }
[[ -f "$HOME/work/proj/.booth/tools/codingbooth.lock" ]] || { echo "FAIL: no lock in project"; exit 1; }
if [[ -f "$HOME/work/.booth/tools/codingbooth.lock" ]]; then
    echo "FAIL: lock written to parent /work"
    exit 1
fi

# --- parent booth install while cwd is a *new* subdir must still target cwd ---
mkdir -p "$HOME/work/other"
cd "$HOME/work/other"
# Invoke parent booth explicitly (what walk-up used to do)
"$HOME/work/booth" install 2>&1
[[ -x "$HOME/work/other/booth" ]] || { echo "FAIL: other has no booth"; exit 1; }
[[ -f "$HOME/work/other/.booth/tools/codingbooth.lock" ]] || { echo "FAIL: no lock in other"; exit 1; }

echo "install-from-central-ok"
BASH
)

assert_contains "$LAST_OUTPUT" "install-from-central-ok"
assert_contains "$LAST_OUTPUT" "✓ Project wrapper:"
assert_contains "$LAST_OUTPUT" "CodingBooth installed"
pass
