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
ARG GO_VERSION=1.25.3

# Setup

RUN "$WS_SETUPS_DIR/go--setup.sh" "${GO_VERSION}"

RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR/go-code-extension--setup.sh" ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" goland  ; fi
