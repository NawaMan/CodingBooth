#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lean-interact--setup.sh — Install LeanInteract (drive Lean from Python and Jupyter) and
# build its Lean REPL for the booth's toolchain at BUILD time.
# EXPERIMENTAL: new, not yet battle-tested.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>]

Examples:
  $0                     # the pinned LeanInteract release
  $0 --version 0.11.6    # a specific release

Notes:
- Needs Python (python--setup.sh) and Lean (lean--setup.sh) already in the image.
- LeanInteract talks to Lean through the Lean REPL, which it clones and builds with lake for
  each Lean version. This script builds it for the booth's default toolchain now, so the
  first LeanREPLConfig() in a notebook does not stop to compile it.
- LeanInteract keeps that cache inside its own package folder, which the booth user cannot
  write. It is redirected to /opt/lean-interact/cache (writable), so a project pinned to
  another toolchain can still build its REPL at run time.
- See: https://github.com/augustepoiroux/LeanInteract
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

VERSION="0.11.6"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:?--version needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a LeanInteract version: '${VERSION}' (expected X.Y.Z)" >&2
  exit 2
fi

[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
export ELAN_HOME="${ELAN_HOME:-/opt/elan}"
export PATH="${ELAN_HOME}/bin:${PATH}"

if ! command -v python >/dev/null 2>&1; then
  echo "❌ Python not found. Select the python template (or run python--setup.sh first)." >&2
  exit 1
fi
if ! command -v lake >/dev/null 2>&1; then
  echo "❌ Lean not found. Select the lean template (or run lean--setup.sh first)." >&2
  exit 1
fi

CACHE_DIR="/opt/lean-interact/cache"

echo "⬇️  Installing LeanInteract ${VERSION} ..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install "lean-interact==${VERSION}" >/dev/null

# Point the package's built-in cache folder at a writable one. It creates the folder on
# import, so a symlink is what keeps the default LeanREPLConfig() working for the booth user.
PKG_DIR="$(python -c 'import importlib.util, os; print(os.path.dirname(importlib.util.find_spec("lean_interact").origin))')"
mkdir -p "$CACHE_DIR"
rm -rf "${PKG_DIR}/cache"
ln -s "$CACHE_DIR" "${PKG_DIR}/cache"

# The REPL cache is a git checkout made by root here and used by the booth user later;
# without this, git refuses it as "dubious ownership".
git config --system --add safe.directory "${CACHE_DIR}/*"

# Build the REPL for the default toolchain, the one `lean` runs outside any project.
LEAN_VER="$(cd / && lean --version | sed -nE 's/^Lean \(version ([^,]+),.*/\1/p')"
if [[ -z "$LEAN_VER" ]]; then
  echo "❌ Could not read the default Lean version from: $(cd / && lean --version)" >&2
  exit 1
fi
echo "🔨 Building the Lean REPL for Lean v${LEAN_VER} ..."
(cd / && python - "v${LEAN_VER}" <<'PY'
import sys
from lean_interact import LeanREPLConfig, LeanServer, Command
config = LeanREPLConfig(lean_version=sys.argv[1], verbose=True)
reply = LeanServer(config).run(Command(cmd="theorem two_plus_two : 2 + 2 = 4 := rfl"))
assert reply.lean_code_is_valid(allow_sorry=False), reply
print("REPL check: 2 + 2 = 4 accepted")
PY
)

# Same layer as the files it covers, so this copies nothing up.
chmod -R a+rwX /opt/lean-interact

echo "✅ LeanInteract installed."
echo "   lean-interact → $(python -m pip show lean-interact 2>/dev/null | sed -n 's/^Version: //p')"
echo "   REPL built for → Lean v${LEAN_VER} (cache: ${CACHE_DIR})"

cat <<EON
ℹ️ Ready to use (Python or a Jupyter cell):
    from lean_interact import LeanREPLConfig, LeanServer, Command
    server = LeanServer(LeanREPLConfig(lean_version="v${LEAN_VER}"))
    server.run(Command(cmd="theorem t : 2 + 2 = 4 := rfl"))
- A Lake project:  LeanREPLConfig(project=LocalProject(directory="."))
- Docs:            https://augustepoiroux.github.io/LeanInteract/
EON
