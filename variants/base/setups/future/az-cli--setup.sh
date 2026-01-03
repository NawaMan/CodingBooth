#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--no-completion]

Examples:
  $0                  # install latest Azure CLI
  $0 --no-completion  # skip bash completion

Notes:
- Installs official Azure CLI from Microsoft apt repo.
- Shared config lives at /opt/az/config (via AZURE_CONFIG_DIR).
- Exposes 'az' via /usr/local/bin (works in non-login shells).
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- args ----
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release apt-transport-https bash-completion
rm -rf /var/lib/apt/lists/*

# ---- add Microsoft apt repo for Azure CLI ----
install -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
CODENAME="$(lsb_release -cs || echo noble)"
ARCH="$(dpkg --print-architecture)"  # amd64 or arm64
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${CODENAME} main" \
  > /etc/apt/sources.list.d/azure-cli.list

apt-get update
apt-get install -y --no-install-recommends azure-cli
rm -rf /var/lib/apt/lists/*

# ---- shared config dir ----
install -d -m 0777 /opt/az/config

# ---- login-shell env ----
cat >/etc/profile.d/99-az--profile.sh <<'EOF'
# Azure CLI shared configuration
export AZURE_CONFIG_DIR=/opt/az/config
EOF
chmod 0644 /etc/profile.d/99-az--profile.sh

# ---- non-login wrapper ----
install -d /usr/local/bin
cat >/usr/local/bin/azwrap <<'EOF'
#!/bin/sh
: "${AZURE_CONFIG_DIR:=/opt/az/config}"
export AZURE_CONFIG_DIR
exec /usr/bin/az "$@"
EOF
chmod +x /usr/local/bin/azwrap
ln -sfn /usr/local/bin/azwrap /usr/local/bin/az

# ---- optional bash completion ----
if [[ $WITH_COMPLETION -eq 1 && -x /usr/bin/az ]]; then
  install -d /etc/bash_completion.d
  az completion -s bash > /etc/bash_completion.d/azure-cli || true
fi

# ---- summary ----
echo "✅ Azure CLI installed."
echo "   AZURE_CONFIG_DIR → /opt/az/config"
echo -n "   az version       → "; az version 2>/dev/null | head -n 1 || true

cat <<'EON'
ℹ️ Ready to use:
- Try: az login   (interactive/device code as appropriate)
- Config is shared at /opt/az/config (persist in CI to cache tokens/profiles if desired).
- Works in login & non-login shells (wrapper sets AZURE_CONFIG_DIR).

Tips:
- Set a default subscription:   az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
- Install extensions as needed: az extension add --name azure-devops
EON
