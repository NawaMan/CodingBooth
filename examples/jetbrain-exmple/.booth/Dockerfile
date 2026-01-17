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
ARG WS_JDK_VERSION=24
ARG WS_JDK_VENDOR=temurin
ARG WS_MVN_VERSION=3.9.11

# Setup

RUN "$WS_SETUPS_DIR/jdk--setup.sh" "${WS_JDK_VERSION}"

# COPY --chmod=0755 ./setups/ /tmp/setups/
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" idea     ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" pycharm  ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" goland   ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" webstorm ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" phpstorm ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" clion    ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" rider    ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" rubymine ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR/jetbrains--setup.sh" datagrip ; fi
