# syntax=docker/dockerfile:1.7
# NPM Example Dockerfile
# Installs popular npm global packages on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN nodejs--setup.sh
RUN npm--install.sh typescript ts-node prettier eslint cowsay figlet-cli
