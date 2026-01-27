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
RUN "$CB_SETUPS/jetbrains--setup.sh" idea
RUN "$CB_SETUPS/jetbrains--setup.sh" pycharm
RUN "$CB_SETUPS/jetbrains--setup.sh" goland
RUN "$CB_SETUPS/jetbrains--setup.sh" webstorm
RUN "$CB_SETUPS/jetbrains--setup.sh" phpstorm
RUN "$CB_SETUPS/jetbrains--setup.sh" clion
RUN "$CB_SETUPS/jetbrains--setup.sh" rider
RUN "$CB_SETUPS/jetbrains--setup.sh" rubymine
RUN "$CB_SETUPS/jetbrains--setup.sh" datagrip

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN "$CB_SETUPS"/antigravity--setup.sh
