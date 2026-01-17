# syntax=docker/dockerfile:1.7
ARG WS_VERSION_TAG=latest
FROM nawaman/workspace:base-${WS_VERSION_TAG}

ARG WS_PY_VERSION=3.12
ARG WS_SETUPS_DIR=/opt/workspace/setups

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

RUN "$WS_SETUPS_DIR/xfce--setup.sh"

# Not really "needed" but feel unuseful without them so put here as a "good starting point".
RUN "$WS_SETUPS_DIR/firefox--setup.sh"
RUN "$WS_SETUPS_DIR/google-chrome--setup.sh"
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

# ---- Cleanup to reduce image size ----
RUN set -euo pipefail \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /opt/pip-cache/* \
  && rm -rf /usr/share/doc/* \
  && rm -rf /usr/share/info/* \
  && rm -rf /var/log/* \
  && rm -rf /var/cache/apt/* \
  && find /opt/google/chrome/locales -type f ! -name "en*" -delete 2>/dev/null || true \
  && find /opt/venvs -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/venvs -type d \( -name "tests" -o -name "test" \) -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/local-pythons -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /usr -name "*.pyc" -type f -delete 2>/dev/null || true

# Copy CodingBooth wallpaper
COPY Wallpaper.png /usr/share/backgrounds/codingbooth-wallpaper.png

# Create XFCE wallpaper config for new users
RUN mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
  && cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorscreen" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/codingbooth-wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

CMD ["start-xfce"]
