# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

ARG PYTHON_VERSION=3.12
RUN python--setup.sh ${PYTHON_VERSION}

RUN kde--setup.sh
RUN firefox--setup.sh
RUN google-chrome--setup.sh
RUN vscode--setup.sh
RUN base-code-extension--setup.sh
RUN bash-code-extension--setup.sh
RUN python-code-extension--setup.sh
RUN jupyter-code-extension--setup.sh
RUN booth-shutdown-code-extension--setup.sh
RUN booth-restart-code-extension--setup.sh
RUN booth-message-desktop-wrapped--setup.sh
RUN booth-desktop-actions--setup.sh
RUN viewmd-desktop-icon--setup.sh
RUN python-nb-kernel--setup.sh
RUN bash-nb-kernel--setup.sh

ARG APT_SNAPSHOT=

# This is so that some basic GTK would work. apt--install.sh (already on PATH
# from the base image) applies APT_SNAPSHOT the same way every setup script does.
RUN apt--install.sh      \
  breeze-gtk-theme        \
  gnome-themes-extra      \
  libgtk-3-0              \
  libcanberra-gtk3-module \
  lxappearance            \
  kde-config-gtk-style

# Cleanup to reduce image size
RUN cleanup-after--setup.sh

# CodingBooth wallpaper: base image already carries wallpaper.png and the
# kde-wallpaper--setup.sh script; this sets it as the KDE default via autostart.
RUN kde-wallpaper--setup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock


CMD ["start-kde-wrapped"]

