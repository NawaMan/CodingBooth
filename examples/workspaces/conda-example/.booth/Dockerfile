# syntax=docker/dockerfile:1.7
# Conda Example Dockerfile

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN conda--setup.sh --python-version 3.12
RUN conda--install.sh numpy
