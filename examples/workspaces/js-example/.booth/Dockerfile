# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

# Customizations
ARG CB_NODE_MAJOR=20
ARG CB_BUN_VERSION=1.3.6
ARG CB_DENO_VERSION=2.6.5


# Setup
WORKDIR /opt/codingbooth/setups

RUN ./claude-code--setup.sh            || [[ $? -eq 42 ]]
RUN ./antigravity--setup.sh            || [[ $? -eq 42 ]]

RUN ./nodejs--setup.sh ${CB_NODE_MAJOR}
RUN ./bun--setup.sh    ${CB_BUN_VERSION}
RUN ./deno--setup.sh   ${CB_DENO_VERSION}

RUN ./react-code-extension--setup.sh   || [[ $? -eq 42 ]]
RUN ./jetbrains--setup.sh webstorm     || [[ $? -eq 42 ]]
