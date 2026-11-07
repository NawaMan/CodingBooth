#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

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

# ---- GitHub's host keys, so the first git-over-SSH needs no yes/no prompt ----
# A booth that brings in only an agent (+agent) or a chosen key folder (+keys) has
# no known_hosts of its own, and a prompt is a hang for `booth -- git push`. These
# are GitHub's published keys (https://api.github.com/meta, "ssh_keys"); a changed
# key still fails loudly, as it should. ~/.ssh/known_hosts is read as well.
KNOWN_HOSTS_FILE="/etc/ssh/ssh_known_hosts"
mkdir -p /etc/ssh
touch "$KNOWN_HOSTS_FILE"
while IFS= read -r line; do
  grep -qxF "$line" "$KNOWN_HOSTS_FILE" || echo "$line" >> "$KNOWN_HOSTS_FILE"
done <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
chmod 644 "$KNOWN_HOSTS_FILE"

# ---- Startup: copy a chosen key folder (openssh+keys) into ~/.ssh ----
# +keys mounts only the folder the user picked, read-only, at /etc/cb-ssh-keys. It is
# not a home seed (/etc/cb-home-seed/.ssh), so it can sit beside +credential, which
# is: Docker refuses two mounts on one target. Copied, never linked, so the host
# folder is not written; existing files win (no-clobber), and ssh's mode rules are
# applied because it refuses a private key others can read. Never fails the start.
STARTUP_FILE="/usr/share/startup.d/60-cb-openssh--startup.sh"
mkdir -p "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

KEYS_DIR="${CB_SSH_KEYS_DIR:-/etc/cb-ssh-keys}"   # override: tests only
SSH_DIR="$HOME/.ssh"

if [[ -d "$KEYS_DIR" ]] && [[ -n "$(ls -A "$KEYS_DIR" 2>/dev/null)" ]]; then
    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
    for src in "$KEYS_DIR"/*; do
        [[ -f "$src" ]] || continue
        dst="$SSH_DIR/$(basename "$src")"
        [[ -e "$dst" ]] && continue
        cp "$src" "$dst" || continue
        case "$dst" in
            *.pub|*/known_hosts|*/known_hosts.*) chmod 644 "$dst" ;;
            *)                                   chmod 600 "$dst" ;;
        esac
    done
fi
true
EOF
chmod 755 "$STARTUP_FILE"

INSTALLED_VERSION=$(ssh -V 2>&1 || true)

echo ""
echo "OpenSSH client installed."
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  $(which ssh)"
echo ""
echo "Commands: ssh, scp, sftp, ssh-keygen, ssh-agent"
echo "Startup:  ${STARTUP_FILE}"
echo "Known hosts: github.com in ${KNOWN_HOSTS_FILE}"
