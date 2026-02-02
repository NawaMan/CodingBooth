# syntax=docker/dockerfile:1.7
# Deno Example Dockerfile
# Installs Deno and some tools on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN deno--setup.sh
RUN deno--install.sh -Agf npm:cowsay
