#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# Lazarus (Free Pascal RAD IDE) setup script

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y>|latest]

Examples:
  $0                     # the Lazarus Ubuntu ships
  $0 --version 4.4       # a specific Lazarus series (apt package lazarus-4.4)

Notes:
- Installs Lazarus from apt, with the GTK2 widgetset
- Always installs lazbuild + the LCL, so Lazarus projects build headless (CI)
- The Lazarus IDE and its desktop icon are added only on a desktop variant
- Pulls in Free Pascal (fpc) if it is not already installed
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
LAZ_VER="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; LAZ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Ubuntu names every Lazarus package after its series (lazarus-4.4, lcl-utils-4.4, ...);
# "latest" is whichever series the unversioned `lazarus` meta-package points at.
if [[ -z "$LAZ_VER" || "$LAZ_VER" == "latest" ]]; then
  CANDIDATE="$(apt-cache policy lazarus | awk '/Candidate:/ {print $2}')"
  [[ -n "$CANDIDATE" && "$CANDIDATE" != "(none)" ]] \
    || { echo "❌ No lazarus package available from apt"; exit 1; }
  LAZ_VER="$(echo "$CANDIDATE" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')"
fi
apt-cache show "lcl-utils-${LAZ_VER}" >/dev/null 2>&1 \
  || { echo "❌ Lazarus ${LAZ_VER} is not available from apt (try: --version latest)"; exit 1; }

# ---- headless toolchain: lazbuild + LCL (GTK2) ----
# libgtk2.0-dev is what lets an LCL program link (-lgtk-x11-2.0); the runtime gtk libs alone do not.
PACKAGES=(
  fpc
  "lcl-utils-${LAZ_VER}"
  "lcl-units-${LAZ_VER}"
  "lcl-gtk2-${LAZ_VER}"
  "lazarus-src-${LAZ_VER}"
  libgtk2.0-dev
)

# ---- the IDE, only where there is a desktop to show it ----
HAS_DESKTOP=0
if cb-has-desktop.sh; then
  HAS_DESKTOP=1
  # fpc-source (FPC sources, for code browsing/completion) and make are what the IDE's
  # first-run check asks for; without them it opens on a "Configure Lazarus IDE" error page.
  PACKAGES+=("lazarus-ide-${LAZ_VER}" "lazarus-ide-gtk2-${LAZ_VER}" "lcl-${LAZ_VER}" "lazarus-${LAZ_VER}"
             fpc-source make)
fi

echo "• Installing Lazarus ${LAZ_VER} ..."
apt-get install -y --no-install-recommends "${PACKAGES[@]}"
rm -rf /var/lib/apt/lists/*

command -v lazbuild >/dev/null || { echo "❌ lazbuild not found after installation"; exit 1; }

# ---- prebuild the LCL ----
# The packaged units are rebuilt by the first lazbuild. Do it once here, as root, so it lands
# in /usr/lib/lazarus instead of in every user's ~/.lazarus on their first build.
WARM_DIR="$(mktemp -d)"
cat >"$WARM_DIR/warm.lpr" <<'EOF'
program warm;
uses Interfaces, Forms;
begin
end.
EOF
cat >"$WARM_DIR/warm.lpi" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <BuildModes><Item Name="Default" Default="True"/></BuildModes>
    <RequiredPackages><Item><PackageName Value="LCL"/></Item></RequiredPackages>
    <Units><Unit><Filename Value="warm.lpr"/><IsPartOfProject Value="True"/></Unit></Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <Target><Filename Value="warm"/></Target>
  </CompilerOptions>
</CONFIG>
EOF
HOME=/root lazbuild -q --primary-config-path="$WARM_DIR/cfg" "$WARM_DIR/warm.lpi" >/dev/null \
  || { echo "❌ lazbuild could not build an LCL program"; exit 1; }
rm -rf "$WARM_DIR"

# ---- desktop icon ----
if [[ $HAS_DESKTOP -eq 1 ]]; then
  cb-desktop-icon.sh lazarus
fi

# ---- summary ----
echo "✅ Lazarus ${LAZ_VER} installed."
echo -n "   lazbuild: "; lazbuild --version 2>&1 | head -1 || true
if [[ $HAS_DESKTOP -eq 0 ]]; then
  echo "ℹ️  No desktop in this booth: lazbuild only (use a desktop variant for the IDE)."
fi

cat <<'EON'
ℹ️ Ready to use:
- lazbuild project.lpi      # build a Lazarus project
- startlazarus              # the Lazarus IDE (desktop variants)
EON
