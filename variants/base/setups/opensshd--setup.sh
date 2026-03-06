#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [PORT]

Arguments:
  PORT  SSH server listen port (default: 2222)

Examples:
  $0           # install with default port 2222
  $0 2200      # use port 2200

Notes:
- Installs OpenSSH server (openssh-client is a prerequisite)
- Uses port 2222 by default (not 22) to avoid conflicts with host SSH
- Password authentication is disabled; key-based auth only
- Host keys are generated on first container start (not at build time)
- The server is NOT started during build (Docker best practice)
- A startup script auto-starts sshd on container boot
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
SSH_PORT="${1:-2222}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- install openssh-server ----
export DEBIAN_FRONTEND=noninteractive
echo "Installing OpenSSH server..."
apt-get update
apt-get install -y --no-install-recommends openssh-server
rm -rf /var/lib/apt/lists/*

# ---- configure sshd ----
SSHD_CONFIG="/etc/ssh/sshd_config.d/codingbooth.conf"
mkdir -p /etc/ssh/sshd_config.d
cat > "${SSHD_CONFIG}" <<SSHD_CONF
# CodingBooth SSH configuration
Port ${SSH_PORT}
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
X11Forwarding yes
PrintMotd yes
AcceptEnv LANG LC_*
SSHD_CONF

# Remove host keys generated at install time — they will be regenerated on first start
rm -f /etc/ssh/ssh_host_*

# Ensure privilege separation directory exists
mkdir -p /run/sshd

# ---- startup script: generate host keys and start sshd ----
STARTUP_FILE="/usr/share/startup.d/55-cb-opensshd--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="__SSH_PORT__"

# Generate host keys if missing (first boot)
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  sudo ssh-keygen -A 2>/dev/null
fi

# Ensure privilege separation directory
sudo mkdir -p /run/sshd

# Set up authorized_keys from cb-home-seed if available
CB_SEED_SSH="/etc/cb-home-seed/.ssh"
SSH_DIR="$HOME/.ssh"
if [[ -d "$CB_SEED_SSH" && ! -f "$SSH_DIR/authorized_keys" ]]; then
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  if [[ -f "$CB_SEED_SSH/authorized_keys" ]]; then
    cp "$CB_SEED_SSH/authorized_keys" "$SSH_DIR/authorized_keys"
  elif [[ -f "$CB_SEED_SSH/id_ed25519.pub" ]]; then
    cp "$CB_SEED_SSH/id_ed25519.pub" "$SSH_DIR/authorized_keys"
  elif [[ -f "$CB_SEED_SSH/id_rsa.pub" ]]; then
    cp "$CB_SEED_SSH/id_rsa.pub" "$SSH_DIR/authorized_keys"
  fi
  if [[ -f "$SSH_DIR/authorized_keys" ]]; then
    chmod 600 "$SSH_DIR/authorized_keys"
  fi
fi

# Start sshd
sudo /usr/sbin/sshd -p "$SSH_PORT"
echo "SSH server started on port $SSH_PORT"
STARTUP
sed -i "s|__SSH_PORT__|${SSH_PORT}|g" "${STARTUP_FILE}"
chmod 755 "${STARTUP_FILE}"

# ---- profile script ----
PROFILE_FILE="/etc/profile.d/55-cb-opensshd--profile.sh"
cat > "${PROFILE_FILE}" <<PROFILE
# OpenSSH server
export CB_SSH_PORT=${SSH_PORT}

opensshd--info() {
  echo "OpenSSH Server"
  echo "  Port:   ${SSH_PORT}"
  echo "  Config: ${SSHD_CONFIG}"
  echo "  Connect: ssh -p ${SSH_PORT} \\\$(whoami)@localhost"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

# ---- summary ----
echo ""
echo "OpenSSH server installed."
echo "  Port:    ${SSH_PORT}"
echo "  Config:  ${SSHD_CONFIG}"
echo "  Startup: ${STARTUP_FILE}"
echo ""
echo "Key-based authentication only (password auth disabled)."
echo "Mount your public key via home-seed or authorized_keys."
echo ""
echo "Connect: ssh -p ${SSH_PORT} \$(whoami)@localhost"
