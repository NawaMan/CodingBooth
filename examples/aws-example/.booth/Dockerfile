# syntax=docker/dockerfile:1.7
# AWS Example Dockerfile
# Installs AWS CLI on top of the base workspace image

ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=0.11.0

FROM nawaman/workspace:${WS_VARIANT_TAG}-${WS_VERSION_TAG}

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
