# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
ARG CB_HAS_NOTEBOOK=false
ARG CB_HAS_VSCODE=false
ARG CB_HAS_DESKTOP=false

# Customizations
ARG GO_VERSION=1.25.3

# Setup

RUN "$CB_SETUPS/go--setup.sh" "${GO_VERSION}"

RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then "$CB_SETUPS/go-code-extension--setup.sh" ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" goland  ; fi
