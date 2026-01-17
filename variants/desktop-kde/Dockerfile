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
  && apt-get purge -y snapd 2>/dev/null || true \
  && rm -rf /var/lib/snapd /var/snap /snap \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /opt/pip-cache/* \
  && rm -rf /usr/share/doc/* \
  && rm -rf /usr/share/info/* \
  && rm -rf /var/log/* \
  && rm -rf /var/cache/apt/* \
  && rm -rf /var/lib/swcatalog/* \
  && rm -rf /usr/share/wallpapers/* \
  && find /usr/share/code -name "*.map" -type f -delete 2>/dev/null || true \
  && find /usr/local/share/code -name "*.map" -type f -delete 2>/dev/null || true \
  && find /opt/google/chrome/locales -type f ! -name "en*" -delete 2>/dev/null || true \
  && find /opt/venvs -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/venvs -type d \( -name "tests" -o -name "test" \) -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/local-pythons -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /usr -name "*.pyc" -type f -delete 2>/dev/null || true

CMD ["start-kde"]
