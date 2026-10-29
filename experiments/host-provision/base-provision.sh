#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# base-provision.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# variants/base/Dockerfile, replayed as a root script on a plain Ubuntu 26.04
# machine or GitHub Actions runner instead of an image build. Each Dockerfile
# step is mirrored in the same order; the ones that make no sense outside a
# container are skipped with a line saying why, so the log doubles as a list.
#
# Usage: sudo CB_TARGET=gha|host base-provision.sh <repo-root>
# -----------------------------------------------------------------------------

set -euo pipefail

REPO="${1:?usage: base-provision.sh <repo-root>}"
BASE="$REPO/variants/base"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CB_TARGET="${CB_TARGET:?CB_TARGET must be gha or host}"
case "$CB_TARGET" in gha|host) ;; *) echo "❌ CB_TARGET=$CB_TARGET: expected gha or host" >&2; exit 1 ;; esac
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

LOCALE=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

step() { printf '\n[base-provision] === %s\n' "$*"; }
skip() { printf '[base-provision] SKIP %s\n' "$*"; }

apt_install() {
  for attempt in 1 2 3 4 5; do
    timeout --kill-after=30 600 apt-get update -o APT::Update::Error-Mode=any && break
    [ "$attempt" -lt 5 ] || exit 1
    sleep $((attempt * 15))
  done
  for attempt in 1 2 3 4 5; do
    timeout --kill-after=30 1800 apt-get install -y --no-install-recommends -o Acquire::Retries=5 "$@" && break
    dpkg --configure -a || true
    [ "$attempt" -lt 5 ] || exit 1
    sleep $((attempt * 15))
  done
}

step "Force IPv4 for apt"
if [ "$CB_TARGET" = "host" ]; then
  skip "99-force-ipv4: a machine-wide apt policy is the owner's choice"
else
  echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99-force-ipv4
fi

step "Shared logs"
touch /tmp/setup.log    ; chmod 777 /tmp/setup.log
touch /tmp/startups.log ; chmod 777 /tmp/startups.log

step "apt packages (both Dockerfile batches; APT_SNAPSHOT not applied)"
apt_install ca-certificates
apt_install bash curl debian-archive-keyring file gettext-base git gnupg less locales sudo tar \
            tini tzdata ttyd unzip wget xz-utils zip
apt_install direnv jq mc nano nginx socat tig tilde tmux tree whiptail zsh

step "tmux defaults"
if [ -e /etc/tmux.conf ] && [ "$CB_TARGET" = "host" ]; then
  skip "/etc/tmux.conf exists: not overwriting the owner's file"
else
  printf '%s\n' 'set -g mouse on' 'set -g set-clipboard on' \
    'set -g status-style "bg=#b9aee0,fg=#2a2440"' > /etc/tmux.conf
fi

step "Locale"
sed -i "s/^#\s*\(${LOCALE}[[:space:]]\+UTF-8\)/\1/" /etc/locale.gen
locale-gen "${LOCALE}"

step "User"
skip "delete 'ubuntu' user, create 'coder', coder NOPASSWD sudoers: the target has its own real user"

step "startup.d + sudo secure_path"
mkdir -p /usr/share/startup.d
printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/codingbooth/setups:/usr/local/uv/bin"\n' \
  > /etc/sudoers.d/50-cb-base-secure-path
chmod 0440 /etc/sudoers.d/50-cb-base-secure-path
visudo -cf /etc/sudoers.d/50-cb-base-secure-path

step "Dockerfile ENV -> /etc/profile.d/00-cb-base-env.sh"
# *-cb-* so booth-entry's step-8 rc block sources it too, not only login shells.
cat > /etc/profile.d/00-cb-base-env.sh <<'EOF'
# Profile: the base image's Dockerfile ENV lines (host-provision experiment).
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export DONT_PROMPT_WSL_INSTALL=1
export EDITOR=fresh
export EXPLORER=mc
export GITVIEW=tig
case ":$PATH:" in *":/opt/codingbooth/setups:"*) ;; *) export PATH="/opt/codingbooth/setups:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
EOF
chmod 644 /etc/profile.d/00-cb-base-env.sh
skip "ENV TERM=xterm-256color: the terminal sets TERM outside a container"
ln -sf /usr/bin/mc  /usr/local/bin/explorer
ln -sf /usr/bin/tig /usr/local/bin/gitview

step "Setups -> /opt/codingbooth/setups"
mkdir -p /opt/codingbooth
rm -rf /opt/codingbooth/setups
cp -a "$BASE/setups" /opt/codingbooth/setups
chmod -R a+rX /opt/codingbooth/setups
find /opt/codingbooth/setups -maxdepth 1 -type f -exec chmod 0755 {} +
mkdir -p /usr/share/backgrounds/codingbooth
install -m 0644 "$BASE/wallpaper.png" "$BASE/wallpaper.jpg" /usr/share/backgrounds/codingbooth/
for f in README.md LICENSE version.txt; do install -m 0644 "$REPO/$f" /opt/codingbooth/; done
install -m 0644 "$REPO/docs/AGENT.md" "$REPO/docs/GUIDE.md" /opt/codingbooth/
rm -rf /opt/codingbooth/docs && cp -a "$REPO/docs" /opt/codingbooth/docs && chmod -R a+rX /opt/codingbooth/docs
skip "_stage/variants: staged by build/docker-build.sh, not needed for setups"
mkdir -p /usr/local/share/codingbooth
install -m 0644 "$REPO/docs/favicon.png" /usr/local/share/codingbooth/favicon.png

step "Baked-in setups (each through a login shell, like the Dockerfile's SHELL bash -lc)"
export PATH="/opt/codingbooth/setups:$PATH"
run_setup() {
  printf '\n[base-provision] --- %s\n' "$*"
  bash -lc "$*"
}
run_setup tls--setup.sh
run_setup viewmd--setup.sh
run_setup gnupg--setup.sh --version 2.5.24
run_setup envfolio--setup.sh
run_setup just--setup.sh
run_setup lazygit--setup.sh
run_setup superfile--setup.sh --version 1.6.0
run_setup differ--setup.sh --version 1.8.1
run_setup "fresh--setup.sh --version 0.5.2 && ln -sf /usr/local/bin/fresh /usr/local/bin/editor"
run_setup fira-code-nerd-font--setup.sh
run_setup ttyd-nerd-font-index--setup.sh
skip "cleanup-after--setup.sh: wipes /tmp, /var/tmp and /root/.cache -- an image-size step, harmful on a live machine"

step "Entry scripts"
install -m 0755 "$HERE/booth-entry"     /usr/local/bin/booth-entry       # the CB_TARGET-guarded copy
install -m 0755 "$HERE/booth--as-coder" /usr/local/bin/booth--as-coder   # the CB_USER_NAME copy
install -m 0755 "$BASE/booth--file-sync" /usr/local/bin/booth--file-sync
install -m 0755 "$BASE/tilde"            /usr/local/bin/tilde
install -m 0644 "$BASE/99z-cb--profile.sh" /etc/profile.d/99z-cb--profile.sh
install -m 0755 "$BASE/99z-cb--startup.sh" /usr/share/startup.d/99z-cb--startup.sh
skip "start-ttyd / start-webconsole / web-ttyd-split: the Console UI is container-only"

echo
echo "[base-provision] ✅ done (CB_TARGET=$CB_TARGET)"
