# syntax=docker/dockerfile:1.7
# Bun Example Dockerfile
# Installs popular Bun global packages on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN bun--setup.sh
RUN bun--install.sh typescript prettier cowsay figlet
