# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# The default value is the latest LTS
ARG CB_PY_VERSION=3.12
ARG CB_JDK_VERSION=24
ARG CB_JDK_VENDOR=temurin
ARG CB_MVN_VERSION=3.9.11

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/codingbooth/setups
ARG CB_VARIANT_TAG="${CB_VARIANT_TAG}"
ARG CB_VERSION_TAG="${CB_VERSION_TAG}"
ARG CB_PY_VERSION="${CB_PY_VERSION}"
ARG CB_JDK_VERSION="${CB_JDK_VERSION}"
ARG CB_JDK_VENDOR="${CB_JDK_VENDOR}"

RUN "$CB_SETUPS"/python--setup.sh ${CB_PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN "$CB_SETUPS"/jdk--setup.sh 25

RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/pycharm--setup.sh                                       ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv ; fi
