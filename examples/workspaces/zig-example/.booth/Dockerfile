# syntax=docker/dockerfile:1.7
# Zig Example Dockerfile

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN zig--setup.sh
