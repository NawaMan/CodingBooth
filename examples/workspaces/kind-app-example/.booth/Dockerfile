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
ARG CB_GO_VERSION=1.25.3
ARG CB_BUN_VERSION=1.3.6

# Setup
WORKDIR /opt/coding-booth/setups

# Setup DinD support
RUN ./dind--setup.sh

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install kind
RUN curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64 \
    && chmod +x ./kind \
    && mv ./kind /usr/local/bin/kind


RUN ./go--setup.sh "${CB_GO_VERSION}"
RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then ./go-code-extension--setup.sh ; fi

RUN ./bun--setup.sh    ${CB_BUN_VERSION}

RUN ./notebook--setup.sh

RUN ./claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then ./antigravity--setup.sh ; fi
