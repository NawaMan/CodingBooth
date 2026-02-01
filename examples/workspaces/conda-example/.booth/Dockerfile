# syntax=docker/dockerfile:1.7
# Conda Example Dockerfile

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN conda--setup.sh --python-version 3.12
RUN conda--install.sh numpy
