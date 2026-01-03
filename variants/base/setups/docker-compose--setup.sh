#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg

# Add Docker’s official GPG key (idempotent)
install -m 0755 -d /etc/apt/keyrings
if [[ ! -s /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Add Docker’s official apt repo (idempotent)
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${codename} stable" \
  > /etc/apt/sources.list.d/docker.list
fi

apt-get update

# Ensure Docker CLI exists (Compose v2 is a CLI plugin)
apt-get install -y docker-ce-cli

# Install Compose v2 plugin
apt-get install -y docker-compose-plugin

echo "✅ Docker Compose v2 installed."
echo "👉 Check: docker compose version"
