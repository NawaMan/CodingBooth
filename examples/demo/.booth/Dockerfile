# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


USER root

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
ARG CB_HAS_NOTEBOOK=false
ARG CB_HAS_VSCODE=false
ARG CB_HAS_DESKTOP=false

# Customizations
ARG JDK_VERSION=25
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11


# Setup
WORKDIR /opt/coding-booth/setups

RUN ./jdk--setup.sh    "${JDK_VERSION}"
RUN ./mvn--setup.sh
RUN ./gradle--setup.sh
RUN ./jenv--setup.sh

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN if [[ "$CB_HAS_DESKTOP"  != false ]]; then ./antigravity--setup.sh ; fi
RUN if [[ "$CB_HAS_DESKTOP"  != false ]]; then ./claude-code--setup.sh ; fi

RUN if [[ "$CB_HAS_VSCODE"   != false ]]; then ./base-code-extension--setup.sh   ; fi
RUN if [[ "$CB_HAS_VSCODE"   != false ]]; then ./bash-code-extension--setup.sh   ; fi
RUN if [[ "$CB_HAS_VSCODE"   != false ]]; then ./python-code-extension--setup.sh ; fi
RUN if [[ "$CB_HAS_VSCODE"   != false ]]; then ./java-code-extension--setup.sh   ; fi
RUN if [[ "$CB_HAS_NOTEBOOK" != false ]]; then ./java-jjava-nb-kernel--setup.sh  ; fi
RUN if [[ "$CB_HAS_NOTEBOOK" != false ]]; then ./bash-nb-kernel--setup.sh        ; fi

WORKDIR /home/coder/code
SHELL ["/bin/bash","-o","pipefail","-lc"]
