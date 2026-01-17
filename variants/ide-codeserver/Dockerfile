# syntax=docker/dockerfile:1.7
ARG WS_VERSION_TAG=latest
FROM nawaman/workspace:base-${WS_VERSION_TAG}

ARG WS_PY_VERSION=3.12
ARG WS_SETUPS_DIR=/opt/workspace/setups

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

RUN "$WS_SETUPS_DIR/python--setup.sh" "${WS_PY_VERSION}"
RUN "$WS_SETUPS_DIR/codeserver--setup.sh"
RUN "$WS_SETUPS_DIR/bash-nb-kernel--setup.sh"

# ---- Cleanup to reduce image size ----
RUN set -euo pipefail \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /opt/pip-cache/* \
    && rm -rf /usr/share/doc/* \
    && rm -rf /usr/share/info/* \
    && rm -rf /var/log/* \
    && find /opt/venvs -type d \( -name "tests" -o -name "test" \) -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venvs -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/local-pythons -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find /usr -name "*.pyc" -type f -delete 2>/dev/null || true

CMD ["codeserver"]
