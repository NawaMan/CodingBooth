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
ARG JDK_VERSION=24
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11


# Setup

# You only need one of the below.

RUN "$WS_SETUPS_DIR"/jdk--setup.sh 25

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN "$WS_SETUPS_DIR"/mvn--setup.sh
RUN "$WS_SETUPS_DIR"/gradle--setup.sh
RUN "$WS_SETUPS_DIR"/jenv--setup.sh

RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR"/java-code-extension--setup.sh                    ; fi
RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh                   ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/eclipse--setup.sh                                ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/idea--setup.sh                                   ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/lombok-eclipse--setup.sh                         ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/jetbrains-plugin--setup.sh idea "Lombook Plugin" ; fi
