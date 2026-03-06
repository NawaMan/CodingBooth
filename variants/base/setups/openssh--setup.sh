#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs OpenSSH client at BUILD time
# --------------------------
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
echo "Installing OpenSSH client..."
apt-get update
apt-get install -y --no-install-recommends openssh-client
rm -rf /var/lib/apt/lists/*

INSTALLED_VERSION=$(ssh -V 2>&1 || true)

echo ""
echo "OpenSSH client installed."
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  $(which ssh)"
echo ""
echo "Commands: ssh, scp, sftp, ssh-keygen, ssh-agent"
