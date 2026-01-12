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

# The default value is the latest LTS
ARG WS_PY_VERSION=3.12

# Customizations

ARG WS_NODE_MAJOR=20
ARG WS_NVM_VERSION=0.40.3


# Setup

RUN "$WS_SETUPS_DIR/nodejs--setup.sh" ${WS_NODE_MAJOR} --nvm-version=${WS_NVM_VERSION}

# Somehow this does not work but install react one below let me use JS and TS.
# RUN if [[ "$WS_HAS_VSCODE" != false ]]; then "$WS_SETUPS_DIR/node-code-extension--setup.sh"  ; fi

RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR/react-code-extension--setup.sh" ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" webstorm   ; fi
