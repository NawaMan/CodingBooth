# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG BOOTH_SETUPS=/opt/codingbooth/setups
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

# Customizations
ARG CB_JDK_VERSION=24
ARG CB_JDK_VENDOR=temurin
ARG CB_MVN_VERSION=3.9.11

# Setup

RUN "$BOOTH_SETUPS/jdk--setup.sh" "${CB_JDK_VERSION}"

# COPY --chmod=0755 ./setups/ /tmp/setups/
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" idea
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" pycharm
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" goland
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" webstorm
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" phpstorm
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" clion
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" rider
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" rubymine
RUN "$BOOTH_SETUPS/jetbrains--setup.sh" datagrip

RUN "$BOOTH_SETUPS"/claude-code--setup.sh
RUN "$BOOTH_SETUPS"/antigravity--setup.sh
