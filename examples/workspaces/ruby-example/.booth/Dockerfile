# syntax=docker/dockerfile:1.7
# Ruby Example Dockerfile
# Installs Ruby and popular gems on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN ruby--setup.sh
RUN gem--install.sh bundler rake pry colorize
