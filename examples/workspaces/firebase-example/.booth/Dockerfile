# syntax=docker/dockerfile:1.7
# Firebase Example Dockerfile
# Installs Firebase CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Install Firebase CLI (includes Node.js)
RUN firebase--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh
