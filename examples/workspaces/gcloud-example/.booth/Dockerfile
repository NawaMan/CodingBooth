# syntax=docker/dockerfile:1.7
# Google Cloud Example Dockerfile
# Installs Google Cloud CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Install Google Cloud CLI
RUN gcloud--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh
