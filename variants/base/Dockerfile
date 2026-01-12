# syntax=docker/dockerfile:1.7

# Dockerfile for workspace container (the base)
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ARG LOCALE=en_US.UTF-8

# Safer default shell
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Update base OS, install packages, generate locale
# NOTE: we intentionally DO NOT install python3-pip (it can pull in an old setuptools)
RUN set -euo pipefail         \
  && apt-get update            \
  && apt-get install           \
  -y                      \
  --no-install-recommends \
  bash                    \
  ca-certificates         \
  curl                    \
  debian-archive-keyring  \
  direnv                  \
  file                    \
  gettext-base            \
  git                     \
  gnupg                   \
  jq                      \
  less                    \
  locales                 \
  mc                      \
  nano                    \
  ranger                  \
  sudo                    \
  tar                     \
  tig                     \
  tilde                   \
  tini                    \
  tmux                    \
  tree                    \
  unzip                   \
  wget                    \
  xz-utils                \
  zip                     \
  zsh                     \
  && sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen \
  && locale-gen "${LOCALE}"

# Fixed values (name & paths). UID/GID come from HOST_UID/HOST_GID at runtime.
ENV USER_NAME=coder  \
  HOME=/home/coder \
  LANG=${LOCALE}   \
  LC_ALL=${LOCALE} \
  WORKSPACE=/home/coder/workspace

# Make the venv default and set pip knobs AFTER the upgrade above
ENV PATH=/opt/workspace/setups:/opt/python/bin:/home/coder/.local/bin:$PATH \
  TERM=xterm-256color \
  EDITOR=tilde

# ---- Belt & suspenders: seed a 'coder' user/group even if 1000 is taken ----
# We pick the first free UID/GID >= 1000 so name lookups always work.
RUN set -eux; \
  free_uid() { local uid=1000; while getent passwd "$uid" >/dev/null; do uid=$((uid+1)); done; echo "$uid"; }; \
  free_gid() { local gid=1000; while getent group  "$gid" >/dev/null; do gid=$((gid+1)); done; echo "$gid"; }; \
  if ! getent group coder >/dev/null; then \
  gid="$(free_gid)"; \
  groupadd -g "$gid" coder; \
  fi; \
  if ! id -u coder >/dev/null 2>&1; then \
  uid="$(free_uid)"; \
  # Do NOT create the home at build time: avoids skel dotfiles with old GID
  useradd -M -u "$uid" -g coder -s /bin/bash coder; \
  fi;

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 workspace-user-setup /usr/local/bin/workspace-user-setup

# Seed dirs
RUN mkdir -p /home/coder/workspace


# Start up - to be run one time at the start of the docker.
RUN mkdir -p /usr/share/startup.d


# --- Shared shell config: copy the profile script ---
COPY --chmod=0644 50-ws-workspace-base--profile.sh /etc/profile.d/50-ws-workspace-base--profile.sh

# --- Make bash and zsh source ALL /etc/profile.d/*.sh for interactive shells ---
RUN set -euo pipefail \
  && mkdir -p /etc/zsh \
  && touch /etc/bash.bashrc /etc/zsh/zshrc

RUN grep -Fq 'profile.d/*.sh' /etc/bash.bashrc || true \
  grep -Fq 'profile.d/*.sh' /etc/zsh/zshrc   || true


# Make sudo see setup scripts (extend secure_path)
RUN set -euo pipefail \
  && printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/workspace/setups:/usr/local/uv/bin"\n' \
  > /etc/sudoers.d/50-workspace-base-secure-path \
  && chmod  0440 /etc/sudoers.d/50-workspace-base-secure-path \
  && visudo -cf  /etc/sudoers.d/50-workspace-base-secure-path

# --- Install the tidy terminal 
RUN apt-get update && apt-get install -y ttyd \
  && rm -rf /var/lib/apt/lists/*

# Suppress the WSL Visual Studio Code prompt
ENV DONT_PROMPT_WSL_INSTALL=1

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 ./setups/ /opt/workspace/setups/

# Set common tools aliases
ENV EDITOR=tilde
ENV EXPLORER=mc
ENV GITVIEW=tig
RUN ln -s /usr/bin/tilde /usr/local/bin/editor
RUN ln -s /usr/bin/mc    /usr/local/bin/explorer
RUN ln -s /usr/bin/tig   /usr/local/bin/gitview

# --- Main workspace profile script with helper functions ---
COPY --chmod=0644 100-ws--profile.sh /etc/profile.d/100-ws--profile.sh

RUN echo "set -g mouse on" >> /etc/tmux.conf

ARG WS_PY_VERSION=3.12
ARG WS_SETUPS_DIR=/opt/workspace/setups


# Always start as root so workspace-user-setup can realign ids
USER root

RUN "$WS_SETUPS_DIR/python--setup.sh" "${WS_PY_VERSION}" 


# ---- Copy startup file: to be executed at first container start ----
COPY --chmod=0755 100-ws--startup.sh /usr/share/startup.d/100-ws--startup.sh

# Workdir
WORKDIR /home/coder/workspace

# tini as PID 1, then run the aligner which execs as 'coder'
# This is needed as the workspace-user-setup will ended up running the CMD which is a chile process
#   so we need tini to handle that properly.
ENTRYPOINT ["tini","-g","--","/usr/local/bin/workspace-user-setup"]

# CMD ["bash","-lc","exec python3 -m http.server 10000 --bind 0.0.0.0 --directory /home/coder/workspace"]
CMD ["bash","-lc","exec ttyd -W -i 0.0.0.0 -p 10000 --writable bash -l"]
