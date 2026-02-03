# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG CB_GO_VERSION=1.25.3
ARG CB_BUN_VERSION=1.3.6

RUN dind--setup.sh
RUN kind--setup.sh
RUN aws-cli--setup.sh

RUN go--setup.sh "${CB_GO_VERSION}"
RUN go-code-extension--setup.sh

RUN bun--setup.sh "${CB_BUN_VERSION}"

RUN python--setup.sh
RUN notebook--setup.sh

RUN claude-code--setup.sh
RUN antigravity--setup.sh

RUN apt update && apt install -y libreoffice libreoffice-gtk3 && rm -rf /var/lib/apt/lists/*