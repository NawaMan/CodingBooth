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
ARG WS_PY_VERSION="${WS_PY_VERSION}"
ARG WS_JDK_VERSION=24
ARG WS_JDK_VENDOR=temurin


# Setup

RUN "$WS_SETUPS_DIR"/python--setup.sh ${WS_PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN "$WS_SETUPS_DIR"/jdk--setup.sh ${WS_JDK_VERSION}

RUN if [[ "$WS_HAS_VSCODE" != false ]]; then "$WS_SETUPS_DIR"/python-code-extension--setup.sh ;  fi
RUN if [[ "$WS_HAS_VSCODE" != false ]]; then "$WS_SETUPS_DIR"/jupyter-code-extension--setup.sh ; fi

RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/pycharm--setup.sh                                       ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv ; fi
