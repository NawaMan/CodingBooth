# syntax=docker/dockerfile:1.7
# Firebase Example Dockerfile
# Installs Firebase CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Install Node.js (required for Firebase CLI)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Firebase CLI globally
RUN npm install -g firebase-tools

# Verify installation
RUN firebase --version

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_HAS_DESKTOP=false

RUN "$CB_SETUPS"/claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then "$CB_SETUPS"/antigravity--setup.sh ; fi
