# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN xfce--setup.sh
RUN firefox--setup.sh
RUN google-chrome--setup.sh
RUN vscode--setup.sh
RUN bash-code-extension--setup.sh
RUN python-code-extension--setup.sh
RUN base-code-extension--setup.sh

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

# Replace default wallpaper with CodingBooth wallpaper -- Hacky but can't do it the proper way
RUN cp /usr/share/backgrounds/xfce/xfce-blue.jpg /usr/share/backgrounds/xfce/xfce-original-wallpaper.jpg
COPY wallpaper.jpg /usr/share/backgrounds/xfce/xfce-blue.jpg

WORKDIR /home/coder/code
CMD ["start-xfce"]
