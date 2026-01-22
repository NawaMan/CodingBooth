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
ARG CB_JDK_VERSION=24
ARG CB_JDK_VENDOR=temurin
ARG CB_MVN_VERSION=3.9.11

# Setup

RUN "$CB_SETUPS/jdk--setup.sh" "${CB_JDK_VERSION}"

# COPY --chmod=0755 ./setups/ /tmp/setups/
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" idea     ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" pycharm  ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" goland   ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" webstorm ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" phpstorm ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" clion    ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" rider    ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" rubymine ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS/jetbrains--setup.sh" datagrip ; fi

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/antigravity--setup.sh ; fi
