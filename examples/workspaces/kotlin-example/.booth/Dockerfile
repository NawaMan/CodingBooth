# syntax=docker/dockerfile:1.7
# Kotlin Example Dockerfile

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

RUN jdk--setup.sh 21
RUN kotlin--setup.sh
