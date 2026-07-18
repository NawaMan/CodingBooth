# syntax=docker/dockerfile:1.7

# Dockerfile for CodingBooth container (the base)
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ARG LOCALE=en_US.UTF-8

# Safer default shell
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Force apt onto IPv4. ports.ubuntu.com (the arm64/ports mirror) publishes AAAA
# records; on build hosts without a working IPv6 route — common for the emulated
# arm64 leg under QEMU — apt prefers IPv6, stalls, and every package fails to
# fetch. This drop-in is inherited by all downstream setups and variants.
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99-force-ipv4


# Setup logs -- setup scripts can use this and user can bind this to host and check the logs.
RUN touch /tmp/setup.log \
  ; chmod 777 /tmp/setup.log

# Startup logs -- startup scripts can use this and user can bind this to host and check the logs.
RUN touch /tmp/startups.log \
  ; chmod 777 /tmp/startups.log


# Update base OS, install packages, generate locale
# NOTE: we intentionally DO NOT install python3-pip (it can pull in an old setuptools)

# Essential system setup
RUN set -euo pipefail \
  ; apt-get update \
  ; apt-get install -y --no-install-recommends \
  bash                   \
  ca-certificates        \
  curl                   \
  debian-archive-keyring \
  file                   \
  gettext-base           \
  git                    \
  gnupg                  \
  less                   \
  locales                \
  sudo                   \
  tar                    \
  tini                   \
  tzdata                 \
  ttyd                   \
  unzip                  \
  wget                   \
  xz-utils               \
  zip                    \
  ; rm -rf /var/lib/apt/lists/*      \
  ; rm -rf /var/cache/apt/archives/* \
  ; rm -rf /var/cache/apt/archives/partial/*


# Optional + niceties
RUN set -euo pipefail \
  ; apt-get update \
  ; apt-get install -y --no-install-recommends \
  direnv \
  jq     \
  mc     \
  nano   \
  nginx  \
  socat  \
  tilde    \
  tig      \
  tmux     \
  tree     \
  whiptail \
  zsh      \
  ; rm -rf /var/lib/apt/lists/*      \
  ; rm -rf /var/cache/apt/archives/* \
  ; rm -rf /var/cache/apt/archives/partial/*

RUN  set -euo pipefail \
  ; sed -i "s/^#\s*\(${LOCALE}[[:space:]]\+UTF-8\)/\1/" /etc/locale.gen \
  ; locale-gen "${LOCALE}"

# Setup locale, PATH and terminal environment
ENV LANG=${LOCALE}
ENV LC_ALL=${LOCALE}
ENV TERM=xterm-256color

# Seed a 'coder' user/group + (clean) home directory safely
# We need to create a brand new user (+group) so that there is no existing home directory (and possible permission problem that might come with it).
# We use -M to not create a home directory so that we can avoid getting the skeleton files when the user is created.
# Then we can create the home directory manually and set the permissions as we want.
#
# Ubuntu 24.04 (noble) ships a stock 'ubuntu' user holding uid/gid 1000. Nothing here
# uses it, but leaving it in place makes free_uid() hand coder 1001 — and 1000 is the
# uid nearly every Linux host has. booth-entry then has to renumber coder on every
# single start (step 4), and re-own $HOME to match (step 5). With large host
# directories bind-mounted under /home/coder — a ~/.m2, a project tree, a .booth/cache
# — that reconcile is slow enough to look like a hang: booths took minutes to start.
# Reclaiming 1000 here makes the uids already agree, so the whole renumber is skipped.
RUN set -euo pipefail \
  ; if id -u ubuntu       >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || userdel ubuntu; fi \
  ; if getent group ubuntu >/dev/null 2>&1; then groupdel ubuntu || true; fi \
  ; free_uid() { local uid=1000; while getent passwd "$uid" >/dev/null; do uid=$((uid+1)); done; echo "$uid"; } \
  ; free_gid() { local gid=1000; while getent group  "$gid" >/dev/null; do gid=$((gid+1)); done; echo "$gid"; } \
  ; if ! getent group coder >/dev/null;      then gid="$(free_gid)"; groupadd -g    "$gid"                       coder; fi \
  ; if ! id -u coder        >/dev/null 2>&1; then uid="$(free_uid)"; useradd  -M -u "$uid" -g coder -s /bin/bash coder; fi \
  ; mkdir -p          /home/coder/code \
  ; chown coder:coder /home/coder      \
  ; chown coder:coder /home/coder/code \
  ; chmod 755         /home/coder      \
  ; chmod 755         /home/coder/code

RUN set -euo pipefail \
  ; echo "coder ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/coder\
  ; chmod 0440 /etc/sudoers.d/coder

# Startup scripts directory - scripts here run once at first container start
RUN mkdir -p /usr/share/startup.d


# Make sudo see setup scripts (extend secure_path)
RUN set -euo pipefail \
  ; printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/codingbooth/setups:/usr/local/uv/bin"\n' \
  > /etc/sudoers.d/50-cb-base-secure-path \
  ; chmod  0440 /etc/sudoers.d/50-cb-base-secure-path \
  ; visudo -cf  /etc/sudoers.d/50-cb-base-secure-path

# Suppress the WSL Visual Studio Code prompt
ENV DONT_PROMPT_WSL_INSTALL=1

# Set common tools aliases
ENV EDITOR=tilde
ENV EXPLORER=mc
ENV GITVIEW=tig
RUN set -euo pipefail                             \
  ; ln -sf /usr/bin/tilde /usr/local/bin/editor   \
  ; ln -sf /usr/bin/mc    /usr/local/bin/explorer \
  ; ln -sf /usr/bin/tig   /usr/local/bin/gitview


# Copy setup scripts and work in that directory
COPY --chmod=0755 ./setups/ /opt/codingbooth/setups/
ENV PATH=/opt/codingbooth/setups:/home/coder/.local/bin:$PATH

# Copy documentation files (staged by build script)
# These provide self-documenting environment for users/agents inside the container
COPY --chmod=0644 ./_stage/README.md   /opt/codingbooth/
COPY --chmod=0644 ./_stage/LICENSE     /opt/codingbooth/
COPY --chmod=0644 ./_stage/version.txt /opt/codingbooth/
COPY --chmod=0644 ./_stage/AGENT.md    /opt/codingbooth/
# Directories need 0755 for traversal; files inside are still readable
COPY ./_stage/variants/ /opt/codingbooth/variants/
RUN chmod -R a+rX /opt/codingbooth/variants
# Documentation (markdown only, ~300KB)
COPY ./_stage/docs/ /opt/codingbooth/docs/
RUN chmod -R a+rX /opt/codingbooth/docs

# WebSocket-to-TCP bridge for booth--expose tunnels

# TLS reverse proxy (Caddy) - activated by BOOTH_TLS=true (set by --public)
RUN tls--setup.sh

# Cleanup to reduce image size
RUN cleanup-after--setup.sh

# Entry that aligns coder's uid/gid to host, then drops privileges
COPY --chmod=0755 booth-entry /usr/local/bin/booth-entry
# Main CodingBooth profile script with helper functions
COPY --chmod=0644 99z-cb--profile.sh /etc/profile.d/99z-cb--profile.sh
# Startup file: to be executed at first container start
COPY --chmod=0755 99z-cb--startup.sh /usr/share/startup.d/99z-cb--startup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock


# tini as PID 1, then run booth-entry which execs CMD as 'coder'
# This is needed as booth-entry ends up running CMD which is a child process,
#   so we need tini to handle signals properly.
ENTRYPOINT ["tini","-g","--","/usr/local/bin/booth-entry"]

# start-ttyd wrapper: supports PASSWORD env var for basic auth
COPY --chmod=0755 start-ttyd /usr/local/bin/start-ttyd
COPY --chmod=0755 start-ttyd-split /usr/local/bin/start-ttyd-split
COPY --chmod=0644 web-ttyd-split/index.html /usr/local/share/ttyd-split/index.html
COPY --chmod=0644 web-ttyd-split/nginx.conf.template /usr/local/share/ttyd-split/nginx.conf.template
RUN chmod 0755 /usr/local/share/ttyd-split

# Shared booth message wrapper infrastructure (nginx + overlay for all variants)
RUN booth-message-wrapper--setup.sh

# By default, start ttyd on port 10000 in the home directory (the online terminal)
CMD ["bash","-lc","exec start-ttyd"]
