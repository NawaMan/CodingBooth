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
ARG JDK_VERSION=24
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11


# Setup
WORKDIR /opt/codingbooth/setups

RUN ./jdk--setup.sh 25

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN ./mvn--setup.sh
RUN ./gradle--setup.sh
RUN ./jenv--setup.sh

RUN ./java-code-extension--setup.sh                    || [[ $? -eq 42 ]]
RUN ./java-jjava-nb-kernel--setup.sh
RUN ./eclipse--setup.sh                                || [[ $? -eq 42 ]]
RUN ./idea--setup.sh                                   || [[ $? -eq 42 ]]
RUN ./lombok-eclipse--setup.sh                         || [[ $? -eq 42 ]]
RUN ./jetbrains-plugin--setup.sh idea "Lombook Plugin" || [[ $? -eq 42 ]]

RUN ./claude-code--setup.sh                            || [[ $? -eq 42 ]]
RUN ./antigravity--setup.sh                            || [[ $? -eq 42 ]]
