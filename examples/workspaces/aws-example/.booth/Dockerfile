# syntax=docker/dockerfile:1.7
# AWS Example Dockerfile
# Installs AWS CLI on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

# Install AWS CLI v2
RUN aws-cli--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh
