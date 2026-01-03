#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--user <username>] [--with-kind] [--with-k3d] [--cluster-name <name>] [--no-helm] [--no-kctx]

Examples:
  $0 --user coder --with-kind --cluster-name dev
  $0 --user dev --with-k3d
  $0 --no-helm --no-kctx

Notes:
- Expects host Docker socket mounted (-v /var/run/docker.sock:/var/run/docker.sock)
- Installs: kubectl, kind, k3d, helm, kubectx/kubens
- Shared kubeconfig: /opt/kube/config
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)."; exit 1; }

# ---------- args ----------
TARGET_USER="${SUDO_USER:-}"
WITH_KIND=0
WITH_K3D=0
CLUSTER_NAME="dev"
WITH_HELM=1
WITH_KCTX=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) shift; TARGET_USER="${1:-}"; shift ;;
    --with-kind) WITH_KIND=1; shift ;;
    --with-k3d)  WITH_K3D=1; shift ;;
    --cluster-name) shift; CLUSTER_NAME="${1:-dev}"; shift ;;
    --no-helm) WITH_HELM=0; shift ;;
    --no-kctx) WITH_KCTX=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
if [[ -z "$TARGET_USER" ]]; then
  CANDIDATE="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
  TARGET_USER="${CANDIDATE:-}"
fi

# ---------- helpers ----------
CURL="curl -fsSL --retry 5 --retry-all-errors --connect-timeout 8 --max-time 300"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) A=x86_64 ; A2=amd64 ;;
  arm64) A=aarch64; A2=arm64 ;;
  *) echo "❌ Unsupported arch: $ARCH (need amd64/arm64)"; exit 1 ;;
esac

log() { printf "\n==> %s\n" "$*"; }

# ---------- base deps ----------
log "Installing base dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  lsb-release apt-transport-https git bash-completion
rm -rf /var/lib/apt/lists/*

# ---------- kubectl (apt repo) ----------
log "Installing kubectl (apt)"
install -d /etc/apt/keyrings
$CURL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y --no-install-recommends kubectl
rm -rf /var/lib/apt/lists/*

# ---------- kind (direct binary) ----------
log "Installing kind"
KIND_URL="https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-${A2}"
$CURL "$KIND_URL" -o /usr/local/bin/kind
chmod +x /usr/local/bin/kind

# ---------- k3d (direct binary; no pipe-to-bash) ----------
if [[ $WITH_K3D -eq 1 ]]; then
  log "Installing k3d"
  # pin a stable version; override with K3D_VERSION env if desired
  K3D_VERSION="${K3D_VERSION:-v5.7.4}"
  $CURL "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${A2}" -o /usr/local/bin/k3d
  chmod +x /usr/local/bin/k3d
fi

# ---------- helm (direct tarball with verification) ----------
if [[ $WITH_HELM -eq 1 ]]; then
  log "Installing Helm"
  HELM_VERSION="${HELM_VERSION:-v3.19.0}"  # pin; override via env
  TMPDIR="$(mktemp -d)"
  HELM_TARBALL="helm-${HELM_VERSION}-linux-${A2}.tar.gz"   # <<< use A2 (amd64/arm64)
  HELM_URL="https://get.helm.sh/${HELM_TARBALL}"
  log "Helm version: ${HELM_VERSION} (URL: ${HELM_URL})"

  # Verify the artifact exists before downloading
  if ! curl -fsSLI "$HELM_URL" >/dev/null; then
    echo "❌ Helm URL not found: ${HELM_URL}"
    echo "   Set HELM_VERSION to a valid release, e.g.: HELM_VERSION=v3.19.0"
    rm -rf "$TMPDIR"
    exit 1
  fi

  $CURL "$HELM_URL" -o "${TMPDIR}/helm.tgz"
  tar -xzf "${TMPDIR}/helm.tgz" -C "$TMPDIR"
  install -m0755 "${TMPDIR}/linux-${A2}/helm" /usr/local/bin/helm   # <<< extracted dir uses A2
  rm -rf "$TMPDIR"

  # Sanity check
  if ! command -v helm >/dev/null 2>&1; then
    echo "❌ Helm install failed"; exit 1
  fi
fi

# ---------- kubectx/kubens ----------
if [[ $WITH_KCTX -eq 1 ]]; then
  log "Installing kubectx/kubens"
  git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
  ln -sfn /opt/kubectx/kubectx /usr/local/bin/kubectx
  ln -sfn /opt/kubectx/kubens  /usr/local/bin/kubens
  install -d /etc/bash_completion.d
  ln -sfn /opt/kubectx/completion/kubectx.bash /etc/bash_completion.d/kubectx
  ln -sfn /opt/kubectx/completion/kubens.bash  /etc/bash_completion.d/kubens
fi

# ---------- shared kubeconfig ----------
log "Preparing shared kubeconfig"
install -d -m 0777 /opt/kube
KCFG="/opt/kube/config"
touch "$KCFG" && chmod 0666 "$KCFG"

# ---------- profile for login shells ----------
cat >/etc/profile.d/99-k8s--profile.sh <<'EOF'
# Kubernetes CLI defaults inside container
export KUBECONFIG=/opt/kube/config
# Docker socket autodetect (only set if empty)
if [ -z "${DOCKER_HOST:-}" ]; then
  if [ -S /var/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
  elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/docker.sock" ]; then
    export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/docker.sock
  fi
fi
EOF
chmod 0644 /etc/profile.d/99-k8s--profile.sh

# ---------- non-login wrappers (no recursion) ----------
log "Creating KUBECONFIG-preserving shims"
/usr/bin/env bash -lc '
set -Eeuo pipefail
for t in kubectl kind helm kubectx kubens k3d; do
  if command -v "$t" >/dev/null 2>&1; then
    REAL_BIN="$(type -P "$t")"
    # skip if already our wrapper
    if [ "$REAL_BIN" = "/usr/local/bin/${t}" ]; then
      continue
    fi
    cat >"/usr/local/bin/${t}" <<EOF
#!/bin/sh
: "\${KUBECONFIG:=/opt/kube/config}"
export KUBECONFIG
exec "$REAL_BIN" "\$@"
EOF
    chmod +x "/usr/local/bin/${t}"
  fi
done
'

# ---------- cluster creation helpers ----------
create_kind_cluster() {
  local name="$1"
  local node_img="${KIND_NODE_IMAGE:-}"
  if [[ -n "$node_img" ]]; then
    kind create cluster --name "$name" --image "$node_img" --kubeconfig "$KCFG"
  else
    kind create cluster --name "$name" --kubeconfig "$KCFG"
  fi
}

create_k3d_cluster() {
  local name="$1"
  k3d cluster create "$name" --wait
  mkdir -p "/root/.kube"
  k3d kubeconfig merge "$name" --switch-context=false --kubeconfig-switch-context=false --kubeconfig-output "$KCFG"
  chmod 0666 "$KCFG" || true
}

# ---------- optionally create cluster ----------
if [[ $WITH_KIND -eq 1 ]]; then
  log "Creating kind cluster '${CLUSTER_NAME}'"
  create_kind_cluster "$CLUSTER_NAME"
fi
if [[ $WITH_K3D -eq 1 ]]; then
  log "Creating k3d cluster '${CLUSTER_NAME}'"
  create_k3d_cluster "$CLUSTER_NAME"
fi

# ---------- docker socket group ----------
if [[ -n "$TARGET_USER" && -S /var/run/docker.sock ]]; then
  log "Granting $TARGET_USER access to host docker socket group"
  SOCK_GID="$(stat -c %g /var/run/docker.sock)"
  if ! getent group | awk -F: '{print $3}' | grep -qx "$SOCK_GID"; then
    groupadd -g "$SOCK_GID" docker-host >/dev/null 2>&1 || true
  fi
  GRP="$(getent group "$SOCK_GID" | cut -d: -f1)"
  [[ -n "$GRP" ]] && usermod -aG "$GRP" "$TARGET_USER" || true
fi

# ---------- summary (non-blocking) ----------
echo "✅ Kubernetes local tooling installed."
echo "   KUBECONFIG  → $KCFG"

# kubectl: force client-only, ignore kubeconfig/plugins, hard timeout, clean env
echo -n "   kubectl     → "
env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  timeout 3s kubectl --kubeconfig=/dev/null --client=true -o=yaml 2>/dev/null | sed -n '1,4p' \
  || echo "not installed"

echo -n "   kind        → "; timeout 3s kind --version 2>/dev/null || echo "not installed"
echo -n "   k3d         → "; timeout 3s k3d version 2>/dev/null   || echo "not installed"
echo -n "   helm        → "; timeout 3s helm version --short 2>/dev/null || echo "not installed"
echo -n "   kubectx     → "; command -v kubectx >/dev/null && echo "ok" || echo "not installed"
echo -n "   kubens      → "; command -v kubens  >/dev/null && echo "ok" || echo "not installed"

cat <<'EON'
ℹ️ Ready to use:
- Start container with host Docker socket:
    docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock <image>

- Create a cluster:
    kind create cluster --name dev
  or
    k3d cluster create dev

- Verify:
    kubectl cluster-info
    kubectl get nodes
EON
