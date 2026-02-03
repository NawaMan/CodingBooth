# syntax=docker/dockerfile:1.7
# Rust Example Dockerfile
# Installs Rust and popular crates on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN rust--setup.sh
RUN cargo--install.sh ripgrep fd-find bat
