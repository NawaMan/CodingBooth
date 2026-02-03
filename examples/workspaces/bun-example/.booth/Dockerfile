# syntax=docker/dockerfile:1.7
# Bun Example Dockerfile
# Installs popular Bun global packages on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN bun--setup.sh
RUN bun--install.sh typescript prettier cowsay figlet
