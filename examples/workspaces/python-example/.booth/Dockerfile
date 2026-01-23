# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/codingbooth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

# Customizations
ARG CB_PY_VERSION="${CB_PY_VERSION}"
ARG CB_JDK_VERSION=24


# Setup
WORKDIR /opt/codingbooth/setups

RUN ./python--setup.sh ${CB_PY_VERSION}

# Needed by pycharm. if you don't use pycharm, remove this.
RUN ./jdk--setup.sh ${CB_JDK_VERSION}

RUN ./python-code-extension--setup.sh                        || [[ $? -eq 42 ]]
RUN ./jupyter-code-extension--setup.sh                       || [[ $? -eq 42 ]]

RUN ./pycharm--setup.sh                                      || [[ $? -eq 42 ]]
RUN ./jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv || [[ $? -eq 42 ]]

RUN ./claude-code--setup.sh                                  || [[ $? -eq 42 ]]
RUN ./antigravity--setup.sh                                  || [[ $? -eq 42 ]]
