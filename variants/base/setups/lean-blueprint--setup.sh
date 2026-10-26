#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lean-blueprint--setup.sh — Install leanblueprint: a LaTeX blueprint of a formalization,
# linked to its Lean declarations, built to PDF and to a web page with a dependency graph.
# EXPERIMENTAL: new, not yet battle-tested.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>]

Examples:
  $0                     # the pinned leanblueprint release
  $0 --version 0.0.20    # a specific release

Notes:
- Needs Python (python--setup.sh) and LaTeX (latex--setup.sh) already in the image.
- Adds what leanblueprint's two builds need beyond them: graphviz (the dependency graph of
  the web version, via pygraphviz, which compiles against it) and XeLaTeX with the Latin
  Modern Math font (the PDF version uses unicode-math).
- The leanblueprint command looks for the project's git repository; run it inside one.
- See: https://github.com/PatrickMassot/leanblueprint
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

VERSION="0.0.20"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:?--version needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a leanblueprint version: '${VERSION}' (expected X.Y.Z)" >&2
  exit 2
fi

[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

if ! command -v python >/dev/null 2>&1; then
  echo "❌ Python not found. Select the python template (or run python--setup.sh first)." >&2
  exit 1
fi
if ! command -v latexmk >/dev/null 2>&1; then
  echo "❌ LaTeX not found. Select the latex template (or run latex--setup.sh first)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
# graphviz + libgraphviz-dev + a compiler: pygraphviz has no binary wheel for Linux.
# texlive-xetex + fonts-lmodern: the PDF is built with xelatex and unicode-math.
apt-get install -y --no-install-recommends \
  graphviz libgraphviz-dev pkg-config build-essential \
  texlive-xetex fonts-lmodern
rm -rf /var/lib/apt/lists/*

echo "⬇️  Installing leanblueprint ${VERSION} ..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install "leanblueprint==${VERSION}" >/dev/null

# The two builds leanblueprint runs, checked directly: plasTeX with the blueprint plugin
# (web) and xelatex (pdf).
python -c 'import leanblueprint.Packages.blueprint, plastexdepgraph, pygraphviz'
xelatex --version | head -1

echo "✅ leanblueprint installed."
echo "   leanblueprint → $(python -m pip show leanblueprint 2>/dev/null | sed -n 's/^Version: //p')"

cat <<'EON'
ℹ️ Ready to use (from a Lean project inside a git repository):
- New blueprint:   leanblueprint new        (asks a few questions, writes blueprint/)
- PDF / web:       leanblueprint pdf   |   leanblueprint web
- Check names:     leanblueprint checkdecls (needs `checkdecls` in the lakefile)
- Everything:      leanblueprint all   |   leanblueprint serve
- Docs:            https://github.com/PatrickMassot/leanblueprint
EON
