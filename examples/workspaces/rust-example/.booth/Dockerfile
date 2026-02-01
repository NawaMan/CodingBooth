# syntax=docker/dockerfile:1.7
# Rust Example Dockerfile
# Installs Rust and popular crates on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN rust--setup.sh
RUN cargo--install.sh ripgrep fd-find bat
