# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:base-${CB_VERSION_TAG}

ARG CB_PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Setup
WORKDIR /opt/coding-booth/setups

RUN ./kde--setup.sh

# Not really "needed" but feel unuseful without them so put here as a "good starting point".
RUN ./firefox--setup.sh
RUN ./google-chrome--setup.sh
RUN ./python--setup.sh "${CB_PY_VERSION}" 
RUN ./vscode--setup.sh
RUN ./jupyter-code-extension--setup.sh
RUN ./bash-code-extension--setup.sh
RUN ./python-code-extension--setup.sh
RUN ./base-code-extension--setup.sh
RUN ./bash-nb-kernel--setup.sh

# This is so that some basic GTK would work.
RUN apt-get update && apt-get install -y \
  breeze-gtk-theme \
  gnome-themes-extra \
  libgtk-3-0 \
  libcanberra-gtk3-module \
  lxappearance \
  kde-config-gtk-style

# ---- Cleanup to reduce image size ----
RUN ./cleanup-after--setup.sh

# Copy CodingBooth wallpaper
COPY wallpaper.png                       /usr/share/backgrounds/codingbooth-wallpaper.png
COPY 99-cb-kde-set-wallpaper--startup.sh /usr/share/startup.d/99-cb-kde-set-wallpaper--startup.sh

WORKDIR /home/coder/code
CMD ["start-kde"]
