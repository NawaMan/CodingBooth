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


# Setup
WORKDIR /opt/codingbooth/setups

RUN ./dind--setup.sh
RUN ./docker-buildx--setup.sh

RUN ./claude-code--setup.sh
RUN ./antigravity--setup.sh

WORKDIR /home/coder/code
