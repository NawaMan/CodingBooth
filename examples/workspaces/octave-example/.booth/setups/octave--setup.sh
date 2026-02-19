#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--packages "pkg1,pkg2,..."]

Examples:
  $0                                       # Install Octave + gnuplot
  $0 --packages "signal,statistics,image"  # Also install Forge packages via apt

Notes:
- Installs GNU Octave and gnuplot (plotting backend) via apt
- Forge packages installed as octave-<name> apt packages
- octave-cli for headless use, octave --gui for desktop variant
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)."; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- args ----
PKGS_LIST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --packages) shift; PKGS_LIST="${1:-}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

set -o pipefail
export DEBIAN_FRONTEND=noninteractive

# ---- install octave ----
echo "📦 Installing GNU Octave..."
apt-get update
apt-get install -y --no-install-recommends \
  octave \
  octave-dev \
  gnuplot \
  ghostscript \
  fonts-freefont-otf \
  fontconfig
rm -rf /var/lib/apt/lists/*

# ---- detect version ----
OCT_BIN="$(command -v octave-cli || command -v octave)"
[[ -x "$OCT_BIN" ]] || { echo "❌ Octave not found after installation."; exit 1; }

OCT_VERSION="$("$OCT_BIN" --version 2>/dev/null | head -n1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo 'unknown')"

# ---- Profile (login shells): environment ----
cat >/etc/profile.d/60-cb-octave--profile.sh <<EOF
# GNU Octave environment
export OCTAVE_VERSION=${OCT_VERSION}
EOF
chmod 0644 /etc/profile.d/60-cb-octave--profile.sh

# ---- Configure gnuplot as default graphics toolkit (suppress warning) ----
# In containers (especially notebooks), gnuplot is the right choice since
# there is no display server for Qt. Setting it explicitly avoids the
# "gnuplot graphics toolkit is discouraged" fallback warning.
install -d /etc/octave
cat >/etc/octave/octaverc <<'OCTRC'
graphics_toolkit("gnuplot");
warning("off", "Octave:GraphicsMagic-Quantum-Depth");
OCTRC

# ---- Optional: install Forge packages via apt ----
if [[ -n "$PKGS_LIST" ]]; then
  IFS=',' read -ra PKGS <<< "$PKGS_LIST"
  APT_PKGS=()
  for pkg in "${PKGS[@]}"; do
    pkg="$(echo "$pkg" | xargs)"  # trim whitespace
    APT_PKGS+=("octave-${pkg}")
  done
  echo "📦 Installing Octave Forge packages: ${APT_PKGS[*]}"
  apt-get update
  apt-get install -y --no-install-recommends "${APT_PKGS[@]}" || true
  rm -rf /var/lib/apt/lists/*
fi

# ---- Summary ----
echo
echo "✅ GNU Octave installed."
echo "   Octave version  → $("$OCT_BIN" --version 2>/dev/null | head -n1)"
echo "   gnuplot          → $(gnuplot --version 2>/dev/null || echo 'not found')"

cat <<'EON'

ℹ️ Ready to use:
- CLI:     octave-cli --version
- GUI:     octave --gui  (requires desktop variant like desktop-xfce)
- Scripts: octave-cli script.m

Tips:
- Install Forge packages from within Octave: pkg install -forge io statistics
- octave-cli is the headless version (for scripts, CI, notebooks).
- octave --gui launches the full IDE (requires a desktop variant).
EON
