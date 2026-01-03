#!/bin/bash

# WARNING: !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# To use add the following to the host docker run: -v /var/run/docker.sock:/var/run/docker.sock  --group-add $(stat -c %g /var/run/docker.sock)
#  .... you would need to change permission /var/run/docker.sock to 777 




set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--user <username>] [--docker-host <unix://...|tcp://...>] [--insecure-perms] [--no-compose] [--no-buildx]

Examples:
  $0 --user coder
  $0 --user dev --insecure-perms
  $0 --docker-host tcp://docker:2375   # if you expose Docker over TCP (no TLS)
  $0 --no-compose --no-buildx          # install only docker CLI

Notes:
- Installs Docker CLI (+ compose & buildx by default) inside the container.
- If /var/run/docker.sock (or a rootless socket) is mounted, configures group access so the user can run 'docker' without sudo.
- Does NOT install or start a Docker daemon.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
TARGET_USER="${SUDO_USER:-}"
CUSTOM_DOCKER_HOST=""
INSECURE_PERMS=0
WITH_COMPOSE=1
WITH_BUILDX=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) shift; TARGET_USER="${1:-}"; shift ;;
    --docker-host) shift; CUSTOM_DOCKER_HOST="${1:-}"; shift ;;
    --insecure-perms) INSECURE_PERMS=1; shift ;;
    --no-compose) WITH_COMPOSE=0; shift ;;
    --no-buildx)  WITH_BUILDX=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- resolve target user (optional but recommended) ----
if [[ -z "$TARGET_USER" ]]; then
  CANDIDATE="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
  TARGET_USER="${CANDIDATE:-}"
fi

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg
rm -rf /var/lib/apt/lists/*

# ---- install Docker CLI + plugins from Docker's official APT repo ----
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
PKGS=( docker-ce-cli )
[[ $WITH_COMPOSE -eq 1 ]] && PKGS+=( docker-compose-plugin )
[[ $WITH_BUILDX -eq 1 ]]  && PKGS+=( docker-buildx-plugin )
apt-get install -y --no-install-recommends "${PKGS[@]}"
rm -rf /var/lib/apt/lists/*

# ---- figure out the Docker socket / host ----
DOCKER_HOST_VALUE=""

if [[ -n "$CUSTOM_DOCKER_HOST" ]]; then
  DOCKER_HOST_VALUE="$CUSTOM_DOCKER_HOST"
else
  if [[ -S /var/run/docker.sock ]]; then
    DOCKER_HOST_VALUE="unix:///var/run/docker.sock"
  else
    if [[ -n "$TARGET_USER" ]]; then
      T_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
      T_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$T_UID}"
      if [[ -S "$T_RUNTIME_DIR/docker.sock" ]]; then
        DOCKER_HOST_VALUE="unix://$T_RUNTIME_DIR/docker.sock"
      fi
    fi
  fi
fi

# ---- make the mounted socket usable without sudo (group fix) ----
if [[ "$DOCKER_HOST_VALUE" =~ ^unix://(.+) ]]; then
  SOCK_PATH="${BASH_REMATCH[1]}"
  if [[ -S "$SOCK_PATH" ]]; then
    SOCK_GID="$(stat -c %g "$SOCK_PATH")"
    if ! getent group | awk -F: '{print $3}' | grep -qx "$SOCK_GID"; then
      groupadd -g "$SOCK_GID" docker-host >/dev/null 2>&1 || true
    fi
    GROUP_NAME="$(getent group "$SOCK_GID" | cut -d: -f1)"
    if [[ -n "$TARGET_USER" && -n "$GROUP_NAME" ]]; then
      usermod -aG "$GROUP_NAME" "$TARGET_USER" || true
    fi
    if [[ $INSECURE_PERMS -eq 1 ]]; then
      chmod 666 "$SOCK_PATH" || true   # WARNING
    fi
  fi
fi

# ---- profile: persist DOCKER_HOST for login shells (esp. when --docker-host is given) ----
cat >/etc/profile.d/99-docker--profile.sh <<EOF
# Docker CLI defaults inside container
if [ -z "\${DOCKER_HOST:-}" ]; then
  ${CUSTOM_DOCKER_HOST:+export DOCKER_HOST=${CUSTOM_DOCKER_HOST}}
  if [ -z "\${DOCKER_HOST:-}" ]; then
    if [ -S /var/run/docker.sock ]; then
      export DOCKER_HOST=unix:///var/run/docker.sock
    elif [ -n "\${XDG_RUNTIME_DIR:-}" ] && [ -S "\$XDG_RUNTIME_DIR/docker.sock" ]; then
      export DOCKER_HOST=unix://\${XDG_RUNTIME_DIR}/docker.sock
    fi
  fi
fi
EOF
chmod 0644 /etc/profile.d/99-docker--profile.sh

# ---- non-login wrapper: ensure DOCKER_HOST for non-login shells ----
install -d /usr/local/bin
cat >/usr/local/bin/dockerwrap <<'EOF'
#!/bin/sh
# docker wrapper to set DOCKER_HOST in non-login shells
DEFAULT_DOCKER_HOST="@DEFAULT_DOCKER_HOST@"
if [ -z "${DOCKER_HOST:-}" ]; then
  if [ -n "$DEFAULT_DOCKER_HOST" ]; then
    export DOCKER_HOST="$DEFAULT_DOCKER_HOST"
  elif [ -S /var/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
  elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/docker.sock" ]; then
    export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/docker.sock
  fi
fi
exec /usr/bin/docker "$@"
EOF
# bake in an explicit host if provided
sed -i "s|@DEFAULT_DOCKER_HOST@|${CUSTOM_DOCKER_HOST}|g" /usr/local/bin/dockerwrap
chmod +x /usr/local/bin/dockerwrap

# Replace docker entrypoint with wrapper via symlink (idempotent)
ln -sfn /usr/local/bin/dockerwrap /usr/local/bin/docker

# (Intentionally DO NOT wrap docker-compose/docker-buildx; use 'docker compose'/'docker buildx')

# ---- summary & quick self-check ----
echo "✅ Docker CLI installed."
echo "   User        : ${TARGET_USER:-(none specified)}"
echo "   DOCKER_HOST : ${DOCKER_HOST_VALUE:-(auto-detect at runtime)}"
if command -v docker >/dev/null 2>&1; then
  echo -n "   docker client → "; docker --version 2>/dev/null || echo "unknown"
  if command -v docker >/dev/null 2>&1; then
    echo -n "   compose plugin → "
    docker compose version 2>/dev/null || echo "not installed"
    echo -n "   buildx plugin  → "
    docker buildx version 2>/dev/null || echo "not installed"
  fi
fi
if [[ -n "$TARGET_USER" ]]; then
  echo "ℹ️ If the user is currently logged in, they may need to re-login (or 'newgrp') to pick up the new group."
fi

cat <<'EON'
ℹ️ Usage:
- Start your dev container with the host socket mounted:
    docker run -it --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      --group-add $(stat -c %g /var/run/docker.sock) \
      <your-image>

- Then inside the container:
    docker ps
    docker buildx ls          # if buildx plugin installed
    docker compose version    # if compose plugin installed

Security notes:
- Mounting the host Docker socket lets the container control the host daemon.
- Use --insecure-perms ONLY if you understand the risks (chmod 666 on the socket).
EON
