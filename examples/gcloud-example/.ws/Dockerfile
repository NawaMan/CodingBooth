# syntax=docker/dockerfile:1.7
# Google Cloud Example Dockerfile
# Installs Google Cloud CLI on top of the base workspace image

ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=latest

FROM nawaman/workspace:${WS_VARIANT_TAG}-${WS_VERSION_TAG}

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
