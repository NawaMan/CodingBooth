# syntax=docker/dockerfile:1.7
# Kind Example Dockerfile
# Installs kind (Kubernetes in Docker) on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Setup DinD support (required for kind)
RUN dind--setup.sh

# Install kind and kubectl
RUN kind--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh
