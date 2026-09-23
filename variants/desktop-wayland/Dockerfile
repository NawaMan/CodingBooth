# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

# Wayland-native desktop: labwc (wlroots) + wayvnc + noVNC.
# See docs/BOOTH_VARIANTS.md and variants/desktop-wayland/README.md.
RUN wayland--setup.sh

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

# Cleanup to reduce image size
RUN cleanup-after--setup.sh

# CodingBooth wallpaper: base image already carries wallpaper.jpg, which
# swaybg reads directly from that branded path — nothing to do here.

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock

CMD ["start-wayland-wrapped"]
