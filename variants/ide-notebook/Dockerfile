# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:base-${CB_VERSION_TAG}

ARG CB_PY_VERSION=3.12
ARG CB_SETUPS_DIR=/opt/coding-booth/setups

# Stay as root so the base ENTRYPOINT (workspace-user-setup) can align uid/gid, then drop to 'coder'
USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

RUN "$CB_SETUPS_DIR/python--setup.sh" "${CB_PY_VERSION}"
RUN "$CB_SETUPS_DIR/notebook--setup.sh"
RUN "$CB_SETUPS_DIR/bash-nb-kernel--setup.sh"

# ---- Cleanup to reduce image size ----
RUN set -euo pipefail \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /opt/pip-cache/* \
  && rm -rf /usr/share/doc/* \
  && rm -rf /usr/share/info/* \
  && rm -rf /var/log/* \
  && find /opt/venvs -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/venvs -type d \( -name "tests" -o -name "test" \) -exec rm -rf {} + 2>/dev/null || true \
  && find /opt/local-pythons -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
  && find /usr -name "*.pyc" -type f -delete 2>/dev/null || true

CMD ["start-notebook"]
