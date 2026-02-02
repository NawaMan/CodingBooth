# syntax=docker/dockerfile:1.7
# Haskell Example Dockerfile
# Uses apt packages for simplicity (faster than ghcup)

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

# Install GHC and Cabal from apt (simpler than ghcup for examples)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ghc cabal-install && \
    rm -rf /var/lib/apt/lists/*
