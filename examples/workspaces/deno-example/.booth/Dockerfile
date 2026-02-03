# syntax=docker/dockerfile:1.7
# Deno Example Dockerfile
# Installs Deno and some tools on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN deno--setup.sh
RUN deno--install.sh -Agf npm:cowsay
