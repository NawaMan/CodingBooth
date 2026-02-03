# syntax=docker/dockerfile:1.7
# Ruby Example Dockerfile
# Installs Ruby and popular gems on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN ruby--setup.sh
RUN gem--install.sh bundler rake pry colorize
