# syntax=docker/dockerfile:1.7
ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=latest
FROM nawaman/workspace:${WS_VARIANT_TAG}-${WS_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG WS_SETUPS_DIR=/opt/workspace/setups
ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=latest
ARG WS_HAS_NOTEBOOK=false
ARG WS_HAS_VSCODE=false
ARG WS_HAS_DESKTOP=false

# Customizations
ARG WS_NODE_MAJOR=20
ARG WS_BUN_VERSION=1.3.6
ARG WS_DENO_VERSION=2.6.5


# Setup

COPY .ws/setups /tmp/setups

RUN /tmp/setups/nodejs--setup.sh ${WS_NODE_MAJOR}
RUN /tmp/setups/bun--setup.sh    ${WS_BUN_VERSION}
RUN /tmp/setups/deno--setup.sh   ${WS_DENO_VERSION}

RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR/react-code-extension--setup.sh" ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" webstorm   ; fi
