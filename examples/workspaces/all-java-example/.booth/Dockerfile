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

RUN "$CB_SETUPS"/jenv--setup.sh

RUN "$CB_SETUPS"/jdk--setup.sh 8
RUN "$CB_SETUPS"/jdk--setup.sh 9
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 10          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 11          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 12          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 13          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 14          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 15          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 16          # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 17
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 18
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 19
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 20
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 21
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
# RUN "$CB_SETUPS"/jdk--setup.sh 22         # Not sure why this does not work in Dockerfile ... but works manually
# RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 23
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 24
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh
RUN "$CB_SETUPS"/jdk--setup.sh 25
RUN "$CB_SETUPS"/java-ijava-nb-kernel--setup.sh

# Force jbang run to not show download afterward.
RUN jbang - 'class Hi { public static void main(String[]a){System.out.println("Hi again");}}'

RUN "$CB_SETUPS"/mvn--setup.sh
RUN "$CB_SETUPS"/gradle--setup.sh

RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then "$CB_SETUPS"/java-code-extension--setup.sh                    ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/eclipse--setup.sh                                ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/idea--setup.sh                                   ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/lombok-eclipse--setup.sh                         ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/jetbrains-plugin--setup.sh idea "Lombook Plugin" ; fi

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/antigravity--setup.sh ; fi
