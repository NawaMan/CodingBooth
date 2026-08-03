# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN xfce--setup.sh

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

# CodingBooth wallpaper: copy to branded path and set as XFCE default via xfconf XML
COPY wallpaper.jpg /usr/share/backgrounds/codingbooth/wallpaper.jpg
COPY wallpaper.png /usr/share/backgrounds/codingbooth/wallpaper.png
COPY xfce-wallpaper--setup.sh /opt/codingbooth/setups/xfce-wallpaper--setup.sh
RUN xfce-wallpaper--setup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock

CMD ["start-xfce-wrapped"]
