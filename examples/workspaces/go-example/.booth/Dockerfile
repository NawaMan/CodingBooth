# syntax=docker/dockerfile:1.7
# Go Example Dockerfile
# Installs popular Go tools on top of the base workspace image

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN go--setup.sh
RUN go--install.sh \
    golang.org/x/tools/gopls@latest \
    github.com/go-delve/delve/cmd/dlv@latest \
    github.com/fatih/gomodifytags@latest
