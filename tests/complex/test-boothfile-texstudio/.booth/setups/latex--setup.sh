#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Installs a TeX Live LaTeX toolchain from Ubuntu's packages, plus latexmk.
#
# TeX Live is large, so the install is tiered by --scheme. Installed sizes on
# Ubuntu 24.04 with --no-install-recommends (measured 2026-09-28):
#   basic        ~150 MB  texlive-latex-base                   pdflatex, core classes
#   recommended  ~190 MB  + texlive-latex-recommended + fonts  hyperref, geometry, booktabs, ...
#   extra        ~380 MB  + texlive-latex-extra                most of what papers \usepackage, TikZ included
#   full         ~7.4 GB  texlive-full                         everything, including every language
#
# Packages go through apt--install.sh, so the APT_SNAPSHOT freeze that
# `booth config` stamps into the Boothfile applies here as well.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--scheme basic|recommended|extra|full]

Examples:
  $0                         # recommended (default)
  $0 --scheme basic          # smallest: pdflatex and the core classes
  $0 --scheme extra          # most CTAN packages a paper or thesis pulls in
  $0 --scheme full           # all of TeX Live (~7 GB)

Notes:
- Always installs latexmk alongside the chosen scheme.
- Versions come from Ubuntu's archive (TeX Live 2023 on 24.04), frozen by APT_SNAPSHOT when set.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- args ----
SCHEME="recommended"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) shift; SCHEME="${1:-recommended}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$SCHEME" in
  basic)       PKGS=(texlive-latex-base) ;;
  recommended) PKGS=(texlive-latex-recommended texlive-fonts-recommended) ;;
  extra)       PKGS=(texlive-latex-extra texlive-fonts-recommended) ;;
  full)        PKGS=(texlive-full) ;;
  *) echo "❌ Unknown scheme: $SCHEME (need basic, recommended, extra, or full)" >&2; usage; exit 2 ;;
esac

echo "📦 Installing TeX Live (${SCHEME}) ..."
apt--install.sh latexmk "${PKGS[@]}"

# ---- friendly summary ----
echo "✅ LaTeX (${SCHEME}) installed."
echo -n "   pdflatex → "; pdflatex --version 2>/dev/null | head -n1 || echo "(not found)"
echo -n "   latexmk  → "; latexmk --version 2>/dev/null | grep -m1 -i 'latexmk' || echo "(not found)"

cat <<'EON'
ℹ️ Ready to use:
- Build a PDF:     latexmk -pdf main.tex
- Rebuild on save: latexmk -pdf -pvc main.tex
- Clean up:        latexmk -c

Notes:
- A missing package ("File `foo.sty' not found") means the scheme is too small:
  pick a larger one (basic < recommended < extra < full).
EON
