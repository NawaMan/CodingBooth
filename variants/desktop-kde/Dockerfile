# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN kde--setup.sh
RUN firefox--setup.sh
RUN google-chrome--setup.sh

ARG PYTHON_VERSION=3.12
RUN python--setup.sh ${PYTHON_VERSION}
RUN vscode--setup.sh
RUN base-code-extension--setup.sh
RUN bash-code-extension--setup.sh
RUN python-code-extension--setup.sh
RUN jupyter-code-extension--setup.sh
RUN bash-nb-kernel--setup.sh

# This is so that some basic GTK would work.
RUN apt-get update        \
  && apt-get install -y   \
  breeze-gtk-theme        \
  gnome-themes-extra      \
  libgtk-3-0              \
  libcanberra-gtk3-module \
  lxappearance            \
  kde-config-gtk-style

# Cleanup to reduce image size
RUN cleanup-after--setup.sh

# Copy CodingBooth wallpaper
COPY wallpaper.png /usr/share/backgrounds/codingbooth-wallpaper.png


CMD ["start-kde"]

