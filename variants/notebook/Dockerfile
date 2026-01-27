# syntax=docker/dockerfile:1.7
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

ARG PYTHON_VERSION=3.12
RUN python--setup.sh ${PYTHON_VERSION}

ARG NOTEBOOK_PORT=10000
RUN notebook--setup.sh ${NOTEBOOK_PORT}

RUN bash-nb-kernel--setup.sh
RUN cleanup-after--setup.sh

CMD ["bash","-lc","exec start-notebook"]
