# syntax=docker/dockerfile:1.7
# Neovim Example Dockerfile
# Installs neovim on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=0.12.0--rc5

FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Install neovim
RUN apt-get update && \
    apt-get install -y --no-install-recommends neovim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_HAS_DESKTOP=false

# Setup
WORKDIR /opt/coding-booth/setups

RUN ./claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then ./antigravity--setup.sh ; fi
