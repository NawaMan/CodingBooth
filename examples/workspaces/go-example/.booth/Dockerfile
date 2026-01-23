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

RUN ./go-code-extension--setup.sh  || [[ $? -eq 42 ]]
RUN ./jetbrains--setup.sh goland   || [[ $? -eq 42 ]]

RUN ./claude-code--setup.sh        || [[ $? -eq 42 ]]
RUN ./antigravity--setup.sh        || [[ $? -eq 42 ]]
