# syntax=docker/dockerfile:1.7
# Google Cloud Example Dockerfile
# Installs Google Cloud CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# TODO - The version should be pinned to a specific version

# Install Google Cloud CLI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    gnupg \
    curl && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt-get update && \
    apt-get install -y google-cloud-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify installation
RUN gcloud --version

ARG CB_SETUPS=/opt/codingbooth/setups

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN "$CB_SETUPS"/antigravity--setup.sh
