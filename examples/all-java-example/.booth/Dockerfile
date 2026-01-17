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

RUN "$WS_SETUPS_DIR"/jenv--setup.sh

RUN "$WS_SETUPS_DIR"/jdk--setup.sh 8
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 9
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 10          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 11          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 12          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 13          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 14          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 15          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
# RUN "$WS_SETUPS_DIR"/jdk--setup.sh 16          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$WS_SETUPS_DIR/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 17
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 18
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 19
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 20
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 21
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 22
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 23
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 24
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh
RUN "$WS_SETUPS_DIR"/jdk--setup.sh 25
RUN "$WS_SETUPS_DIR"/java-ijava-nb-kernel--setup.sh

# Force jbang run to not show download afterward.
RUN jbang - 'class Hi { public static void main(String[]a){System.out.println("Hi again");}}'

RUN "$WS_SETUPS_DIR"/mvn--setup.sh
RUN "$WS_SETUPS_DIR"/gradle--setup.sh

RUN if [[ "$WS_HAS_VSCODE"  != false ]]; then "$WS_SETUPS_DIR"/java-code-extension--setup.sh                    ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/eclipse--setup.sh                                ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/idea--setup.sh                                   ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/lombok-eclipse--setup.sh                         ; fi
RUN if [[ "$WS_HAS_DESKTOP" != false ]]; then "$WS_SETUPS_DIR"/jetbrains-plugin--setup.sh idea "Lombook Plugin" ; fi
