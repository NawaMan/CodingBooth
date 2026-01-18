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
ARG CB_PY_VERSION="${CB_PY_VERSION}"
ARG CB_JDK_VERSION=24


# Setup

RUN "$CB_SETUPS"/python--setup.sh ${CB_PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN "$CB_SETUPS"/jdk--setup.sh ${CB_JDK_VERSION}

RUN if [[ "$CB_HAS_VSCODE" != false ]]; then "$CB_SETUPS"/python-code-extension--setup.sh ;  fi
RUN if [[ "$CB_HAS_VSCODE" != false ]]; then "$CB_SETUPS"/jupyter-code-extension--setup.sh ; fi

RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/pycharm--setup.sh                                       ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv ; fi
