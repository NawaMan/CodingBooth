# syntax=docker/dockerfile:1.7
# Haskell Example Dockerfile
# Uses apt packages for simplicity (faster than ghcup)

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

# Install GHC and Cabal from apt (simpler than ghcup for examples)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ghc cabal-install && \
    rm -rf /var/lib/apt/lists/*
