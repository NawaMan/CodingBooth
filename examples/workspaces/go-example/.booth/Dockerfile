# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/codingbooth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

# Customizations
ARG CB_GO_VERSION=1.25.3

# Setup
WORKDIR /opt/codingbooth/setups

RUN ./go--setup.sh "${CB_GO_VERSION}"

RUN ./go-code-extension--setup.sh
RUN ./jetbrains--setup.sh goland

RUN ./claude-code--setup.sh
RUN ./antigravity--setup.sh
