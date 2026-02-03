# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG BOOTH_SETUPS=/opt/codingbooth/setups
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

# Customizations


# Setup
WORKDIR /opt/codingbooth/setups

RUN ./dind--setup.sh
RUN ./docker-buildx--setup.sh

RUN ./claude-code--setup.sh
RUN ./antigravity--setup.sh

WORKDIR /home/coder/code
