# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}

ARG CB_PY_VERSION=3.12

USER root
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Setup
WORKDIR /opt/codingbooth/setups

RUN ./python--setup.sh "${CB_PY_VERSION}"
RUN ./codeserver--setup.sh
RUN ./bash-nb-kernel--setup.sh
RUN ./cleanup-after--setup.sh

WORKDIR /home/coder/code
CMD ["codeserver"]
