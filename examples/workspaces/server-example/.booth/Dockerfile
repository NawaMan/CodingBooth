# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG PY_VERSION=3.12
RUN python--setup.sh ${PY_VERSION}

RUN claude-code--setup.sh
RUN antigravity--setup.sh
