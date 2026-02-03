# syntax=docker/dockerfile:1.7
# Pip Example Dockerfile
# Installs popular Python packages on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN python--setup.sh
RUN pip--install.sh httpx rich click pytest black ruff cowsay pyfiglet
