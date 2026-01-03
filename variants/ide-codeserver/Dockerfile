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

CMD ["codeserver"]
