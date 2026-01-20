# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:base-${CB_VERSION_TAG}

WORKDIR /opt/coding-booth/setups

RUN ./notebook--setup.sh
RUN ./bash-nb-kernel--setup.sh
RUN ./cleanup-after--setup.sh

# Workdir
WORKDIR /home/coder/code
SHELL   ["/bin/bash","-o","pipefail","-lc"]
CMD     ["start-notebook"]
