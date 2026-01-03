#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <vX.Y.Z>] [--no-official-repo] [--no-completion]

Examples:
  $0                            # latest kubectl from official repo
  $0 --version v1.30.3          # pin exact kubectl version
  $0 --no-official-repo         # use distro's kubectl if repo unavailable
  $0 --no-completion            # skip bash completion
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)."; exit 1; }

# Defaults / args
PIN_VER=""            # e.g. v1.30.3 (must include the 'v' if used)
USE_OFFICIAL=1
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; PIN_VER="${1:-}"; shift ;;
    --no-official-repo) USE_OFFICIAL=0; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  endcase
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release bash-completion
rm -rf /var/lib/apt/lists/*

install_from_official() {
  install -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
    >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  if [[ -n "$PIN_VER" ]]; then
    # Install exact version via .deb URL if apt pinning isn’t trivial
    ARCH="$(dpkg --print-architecture)"
    case "$ARCH" in
      amd64) KARCH="amd64" ;; arm64) KARCH="arm64" ;; *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
    esac
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    DEB_URL="https://pkgs.k8s.io/tools/kubectl/${PIN_VER}/deb/kubectl_${PIN_VER#v}-1.1_${KARCH}.deb"
    echo "⬇️  Downloading kubectl ${PIN_VER} .deb ..."
    curl -fsSL "$DEB_URL" -o "$TMP/kubectl.deb"
    apt-get install -y --no-install-recommends "$TMP/kubectl.deb"
  else
    apt-get install -y --no-install-recommends kubectl
  fi
  rm -rf /var/lib/apt/lists/*
}

install_from_distro() {
  apt-get update
  apt-get install -y --no-install-recommends kubectl || {
    echo "❌ kubectl not available in distro repos"; exit 1;
  }
  rm -rf /var/lib/apt/lists/*
}

if [[ $USE_OFFICIAL -eq 1 ]]; then
  install_from_official
else
  install_from_distro
fi

# Shared kubeconfig
install -d -m 0777 /opt/kube
KCFG="/opt/kube/config"
touch "$KCFG" && chmod 0666 "$KCFG"

# Login shells: set KUBECONFIG
cat >/etc/profile.d/99-kubectl--profile.sh <<'EOF'
export KUBECONFIG=/opt/kube/config
EOF
chmod 0644 /etc/profile.d/99-kubectl--profile.sh

# Non-login shells: tiny wrapper so kubectl sees the shared config
install -d /usr/local/bin
cat >/usr/local/bin/kubectlwrap <<'EOF'
#!/bin/sh
: "${KUBECONFIG:=/opt/kube/config}"
export KUBECONFIG
exec /usr/bin/kubectl "$@"
EOF
chmod +x /usr/local/bin/kubectlwrap
ln -sfn /usr/local/bin/kubectlwrap /usr/local/bin/kubectl

# Optional bash completion
if [[ $WITH_COMPLETION -eq 1 && -x /usr/bin/kubectl ]]; then
  install -d /etc/bash_completion.d
  /usr/bin/kubectl completion bash >/etc/bash_completion.d/kubectl 2>/dev/null || true
fi

# Summary
echo "✅ kubectl installed."
echo "   KUBECONFIG → $KCFG"
echo -n "   Client     → "; /usr/bin/kubectl version --client --output=yaml 2>/dev/null | sed -n '1,4p'

cat <<'EON'
ℹ️ Ready to use:
- Place or merge your kubeconfigs into /opt/kube/config
- Try: kubectl config get-contexts
- Works in login & non-login shells (wrapper sets KUBECONFIG)

Tips:
- Merge another kubeconfig: KUBECONFIG=/opt/kube/config:/path/other kubeconfig kubectl config view --flatten > /opt/kube/config.new && mv /opt/kube/config.new /opt/kube/config
- To add kubectx/kubens later: apt-get install -y git && git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx && ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx && ln -s /opt/kubectx/kubens /usr/local/bin/kubens
EON
