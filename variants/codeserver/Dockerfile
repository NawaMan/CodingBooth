# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
ARG FINAL_STAGE=base
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG} AS base

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

ARG PYTHON_VERSION=3.12
RUN python--setup.sh ${PYTHON_VERSION}
ARG CODESERVER_PORT=10000
RUN codeserver--setup.sh ${CODESERVER_PORT}
RUN jupyter-code-extension--setup.sh
RUN bash-code-extension--setup.sh
RUN booth-shutdown-code-extension--setup.sh
RUN booth-restart-code-extension--setup.sh
RUN booth-message-code-extension--setup.sh
RUN bash-nb-kernel--setup.sh
RUN cleanup-after--setup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock

CMD ["bash","-lc","exec start-codeserver"]
