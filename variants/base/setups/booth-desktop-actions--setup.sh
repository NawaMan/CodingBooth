#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-desktop-actions--setup.sh
#
# Hijacks system power actions (shutdown, reboot, poweroff) so that desktop
# environments (XFCE, KDE, LXQt) call booth--shutdown / booth--restart
# instead of the real (non-functional) system commands.
#
# Must be run as root during image build.
# -----------------------------------------------------------------------------

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

SETUPS_DIR="${SETUPS_DIR:-/opt/codingbooth/setups}"

echo "🔧 Setting up desktop power action wrappers..."

# Ensure a GUI dialog tool is available for confirmation prompts
if ! command -v zenity >/dev/null 2>&1 && ! command -v kdialog >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq zenity >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 1. Wrapper scripts for system commands
#
#    Desktop environments call these when the user clicks Shutdown/Restart
#    in the logout dialog. In a container there is no systemd, so we redirect
#    to booth--shutdown / booth--restart.
# ---------------------------------------------------------------------------

# Save originals (if they exist and aren't already our wrappers)
for cmd in poweroff reboot shutdown; do
  real="$(command -v "$cmd" 2>/dev/null || true)"
  if [[ -n "$real" && ! -L "$real" ]]; then
    # Only back up real binaries, not symlinks we already created
    if ! grep -q 'booth--' "$real" 2>/dev/null; then
      mv "$real" "${real}.real" 2>/dev/null || true
    fi
  fi
done

# poweroff → booth--shutdown
cat > /usr/local/bin/poweroff <<'WRAPPER'
#!/bin/bash
exec booth--shutdown
WRAPPER
chmod +x /usr/local/bin/poweroff

# reboot → booth--restart
cat > /usr/local/bin/reboot <<'WRAPPER'
#!/bin/bash
exec booth--restart --yes
WRAPPER
chmod +x /usr/local/bin/reboot

# shutdown → booth--shutdown (ignores flags like -h, -r, etc.)
cat > /usr/local/bin/shutdown <<'WRAPPER'
#!/bin/bash
# Parse flags to detect reboot vs halt
for arg in "$@"; do
  case "$arg" in
    -r|--reboot) exec booth--restart --yes ;;
  esac
done
exec booth--shutdown
WRAPPER
chmod +x /usr/local/bin/shutdown

# systemctl wrapper for power actions only (pass-through for everything else)
cat > /usr/local/bin/systemctl <<'WRAPPER'
#!/bin/bash
case "${1:-}" in
  poweroff|halt)   exec booth--shutdown      ;;
  reboot|restart)  exec booth--restart --yes ;;
  *)
    # Pass through to real systemctl if it exists
    if [[ -x /usr/local/bin/systemctl.real ]]; then
      exec /usr/local/bin/systemctl.real "$@"
    elif [[ -x /usr/bin/systemctl ]]; then
      exec /usr/bin/systemctl "$@"
    else
      echo "systemctl: command not available in this container" >&2
      exit 1
    fi
    ;;
esac
WRAPPER
chmod +x /usr/local/bin/systemctl

# Back up real systemctl if it exists and isn't already our wrapper
if [[ -x /usr/bin/systemctl ]] && ! grep -q 'booth--' /usr/bin/systemctl 2>/dev/null; then
  cp /usr/bin/systemctl /usr/local/bin/systemctl.real 2>/dev/null || true
fi

echo "  ✔ Power action wrappers installed"
echo "✅ Desktop power actions setup complete"
