# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG}

# The least memory a booth from this image needs. Engine apple (Apple container)
# runs each booth in its own VM, 1 GB by default, which a desktop outgrows; the
# CLI gives the VM this much when no --vm-memory is set. Images built FROM this
# one inherit it. Docker and Podman ignore it. See docs/CONTAINER_SUPPORT.md.
LABEL com.codingbooth.vm-memory-min="4g"

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN xfce--setup.sh
# Modern look. The packs only install; xfce-theme--setup.sh then picks the
# defaults (Greybird-dark apps and windows, Reversal-dark icons, Gruppled White
# cursor), so it runs after them. Only the default look is installed; other
# themes are opt-in templates. Switch in the booth with booth--theme. Plank seeds
# its launchers on first login, so the browsers and VS Code installed below
# still land on the dock.
RUN reversal-icons--setup.sh
RUN gruppled-cursors--setup.sh
RUN xfce-theme--setup.sh
RUN plank--setup.sh

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

# CodingBooth wallpaper: base image already carries wallpaper.jpg and the
# xfce-wallpaper--setup.sh script; this sets it as the XFCE default via xfconf XML.
RUN xfce-wallpaper--setup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock

CMD ["start-xfce-wrapped"]
