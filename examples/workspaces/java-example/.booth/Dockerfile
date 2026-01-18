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
ARG JDK_VERSION=24
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11


# Setup

# You only need one of the below.

RUN "$CB_SETUPS"/jdk--setup.sh 25

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN "$CB_SETUPS"/mvn--setup.sh
RUN "$CB_SETUPS"/gradle--setup.sh
RUN "$CB_SETUPS"/jenv--setup.sh

RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then "$CB_SETUPS"/java-code-extension--setup.sh                    ; fi
RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh                   ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/eclipse--setup.sh                                ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/idea--setup.sh                                   ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/lombok-eclipse--setup.sh                         ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/jetbrains-plugin--setup.sh idea "Lombook Plugin" ; fi
