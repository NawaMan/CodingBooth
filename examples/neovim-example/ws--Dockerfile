# syntax=docker/dockerfile:1.7
# Neovim Example Dockerfile
# Installs neovim on top of the base workspace image

ARG WS_VARIANT_TAG=base
ARG WS_VERSION_TAG=0.11.0

FROM nawaman/workspace:${WS_VARIANT_TAG}-${WS_VERSION_TAG}

# Install neovim
RUN apt-get update && \
    apt-get install -y --no-install-recommends neovim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
