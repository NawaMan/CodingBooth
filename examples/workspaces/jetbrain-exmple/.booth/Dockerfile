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
ARG CB_JDK_VERSION=24
ARG CB_JDK_VENDOR=temurin
ARG CB_MVN_VERSION=3.9.11

# Setup

RUN "$CB_SETUPS/jdk--setup.sh" "${CB_JDK_VERSION}"

# COPY --chmod=0755 ./setups/ /tmp/setups/
RUN "$CB_SETUPS/jetbrains--setup.sh" idea     || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" pycharm  || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" goland   || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" webstorm || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" phpstorm || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" clion    || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" rider    || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" rubymine || [[ $? -eq 42 ]]
RUN "$CB_SETUPS/jetbrains--setup.sh" datagrip || [[ $? -eq 42 ]]

RUN "$CB_SETUPS"/claude-code--setup.sh        || [[ $? -eq 42 ]]
RUN "$CB_SETUPS"/antigravity--setup.sh        || [[ $? -eq 42 ]]
