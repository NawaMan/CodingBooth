# syntax=docker/dockerfile:1.7
ARG WS_VERSION_TAG=latest
FROM nawaman/workspace:base-${WS_VERSION_TAG}

ARG WS_PY_VERSION=3.12
ARG WS_SETUPS_DIR=/opt/workspace/setups

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

RUN "$WS_SETUPS_DIR/kde--setup.sh"

# Not really "needed" but feel unuseful without them so put here as a "good starting point".
RUN "$WS_SETUPS_DIR/firefox--setup.sh"
RUN "$WS_SETUPS_DIR/google-chrome--setup.sh"
RUN "$WS_SETUPS_DIR/chromium-browser--setup.sh"
RUN "$WS_SETUPS_DIR/python--setup.sh" "${WS_PY_VERSION}" 
RUN "$WS_SETUPS_DIR/vscode--setup.sh"
RUN "$WS_SETUPS_DIR/jupyter-code-extension--setup.sh"
RUN "$WS_SETUPS_DIR/bash-code-extension--setup.sh"
RUN "$WS_SETUPS_DIR/python-code-extension--setup.sh"
RUN "$WS_SETUPS_DIR/base-code-extension--setup.sh"
RUN "$WS_SETUPS_DIR/bash-nb-kernel--setup.sh"

# This is so that some basic GTK would work.
RUN apt-get update && apt-get install -y \
        breeze-gtk-theme \
        gnome-themes-extra \
        libgtk-3-0 \
        libcanberra-gtk3-module \
        lxappearance \
        kde-config-gtk-style


CMD ["start-kde"]
