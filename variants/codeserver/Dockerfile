# syntax=docker/dockerfile:1.7
ARG BOOTH_VERSION_TAG=latest
ARG FINAL_STAGE=base
FROM nawaman/codingbooth:base-${BOOTH_VERSION_TAG} AS base

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

ARG PYTHON_VERSION=3.12
RUN python--setup.sh ${PYTHON_VERSION}
# No port: start-codeserver keeps the setup's own default (13333), which is also
# the port start-codeserver-wrapped runs this variant's code-server on behind the
# booth port. A 10000 here made a bare `start-codeserver` aim at the booth port.
RUN codeserver--setup.sh
RUN jupyter-code-extension--setup.sh
RUN bash-code-extension--setup.sh
RUN booth-shutdown-code-extension--setup.sh
RUN booth-restart-code-extension--setup.sh
RUN booth-web-preview-code-extension--setup.sh
RUN booth-message-codeserver-wrapped--setup.sh
RUN bash-nb-kernel--setup.sh
RUN cleanup-after--setup.sh

# Clear the lock
RUN rm -f /etc/.pwd.lock /etc/passwd.lock /etc/shadow.lock /etc/group.lock

CMD ["bash","-lc","exec start-codeserver-wrapped"]
