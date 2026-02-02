# syntax=docker/dockerfile:1.7
# Pip Example Dockerfile
# Installs popular Python packages on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN python--setup.sh
RUN pip--install.sh httpx rich click pytest black ruff cowsay pyfiglet
