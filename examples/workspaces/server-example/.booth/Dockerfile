# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG PY_VERSION=3.12
RUN python--setup.sh ${PY_VERSION}

RUN claude-code--setup.sh || [[ $? -eq 42 ]]
RUN antigravity--setup.sh || [[ $? -eq 42 ]]
