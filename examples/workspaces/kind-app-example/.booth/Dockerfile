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
ARG CB_GO_VERSION=1.25.3
ARG CB_BUN_VERSION=1.3.6

# Setup
WORKDIR /opt/codingbooth/setups

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
RUN ./go-code-extension--setup.sh

RUN ./bun--setup.sh    ${CB_BUN_VERSION}

RUN ./notebook--setup.sh

RUN ./claude-code--setup.sh
RUN ./antigravity--setup.sh

# Install AWS CLI v2
RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip curl && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify installation
RUN aws --version
