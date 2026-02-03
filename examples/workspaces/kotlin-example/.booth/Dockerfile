# syntax=docker/dockerfile:1.7
# Kotlin Example Dockerfile

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN jdk--setup.sh 21
RUN kotlin--setup.sh
