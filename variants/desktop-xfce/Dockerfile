# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:base-${CB_VERSION_TAG}

ARG CB_PY_VERSION=3.12

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Setup
WORKDIR /opt/coding-booth/setups

RUN ./xfce--setup.sh

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
COPY wallpaper.png /usr/share/backgrounds/codingbooth-wallpaper.png

# Create XFCE wallpaper config for new users
RUN mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
  && cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/codingbooth-wallpaper.png"/>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/codingbooth-wallpaper.png"/>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/codingbooth-wallpaper.png"/>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/codingbooth-wallpaper.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

WORKDIR /home/coder/code
CMD ["start-xfce"]
