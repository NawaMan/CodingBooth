# syntax=docker/dockerfile:1.7
# Kind Example Dockerfile
# Installs kind (Kubernetes in Docker) on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

# Setup DinD support (required for kind)
RUN dind--setup.sh

# Install kind and kubectl
RUN kind--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh
