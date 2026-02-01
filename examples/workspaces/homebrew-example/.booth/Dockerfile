# syntax=docker/dockerfile:1.7
# AWS Example Dockerfile
# Installs AWS CLI on top of the base workspace image

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN homebrew--setup.sh
RUN brew--install.sh bat neovim imagemagick node ffmpeg gcc postgresql redis nginx
