# syntax=docker/dockerfile:1.7
# AWS Example Dockerfile
# Installs AWS CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=0.12.0--rc6

FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

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

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_HAS_DESKTOP=false

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/antigravity--setup.sh ; fi
