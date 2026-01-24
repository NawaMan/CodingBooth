# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
ARG FINAL_STAGE=base
FROM nawaman/codingbooth:base-${CB_VERSION_TAG} AS base

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN codeserver--setup.sh
RUN cleanup-after--setup.sh

CMD ["bash","-lc","exec codeserver"]
