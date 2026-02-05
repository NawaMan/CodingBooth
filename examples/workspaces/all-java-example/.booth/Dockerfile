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
ARG JDK_VERSION=24
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11


# Setup

# You only need one of the below.

RUN "$BOOTH_SETUPS"/jenv--setup.sh

RUN "$BOOTH_SETUPS"/jdk--setup.sh 8
RUN "$BOOTH_SETUPS"/jdk--setup.sh 9
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 10          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 11          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 12          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 13          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 14          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 15          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 16          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 17
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 18
# RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 19
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 20
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 21
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
# RUN "$BOOTH_SETUPS"/jdk--setup.sh 22         # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 23
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 24
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$BOOTH_SETUPS"/jdk--setup.sh 25
RUN "$BOOTH_SETUPS"/java-ijava-nb-kernel--setup.sh

# Force jbang run to not show download afterward.
RUN jbang - 'class Hi { public static void main(String[]a){System.out.println("Hi again");}}'

RUN "$BOOTH_SETUPS"/mvn--setup.sh
RUN "$BOOTH_SETUPS"/gradle--setup.sh

RUN "$BOOTH_SETUPS"/java-code-extension--setup.sh
RUN "$BOOTH_SETUPS"/eclipse--setup.sh
RUN "$BOOTH_SETUPS"/idea--setup.sh
RUN "$BOOTH_SETUPS"/lombok-eclipse--setup.sh
RUN "$BOOTH_SETUPS"/jetbrains-plugin--setup.sh idea "Lombook Plugin"

RUN "$BOOTH_SETUPS"/claude-code--setup.sh
RUN "$BOOTH_SETUPS"/antigravity--setup.sh
