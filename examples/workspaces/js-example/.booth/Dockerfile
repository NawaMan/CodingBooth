# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
ARG CB_HAS_NOTEBOOK=false
ARG CB_HAS_VSCODE=false
ARG CB_HAS_DESKTOP=false

# Customizations
ARG CB_NODE_MAJOR=20
ARG CB_BUN_VERSION=1.3.6
ARG CB_DENO_VERSION=2.6.5


# Setup
WORKDIR /opt/coding-booth/setups

RUN ./antigravity--setup.sh
RUN ./nodejs--setup.sh ${CB_NODE_MAJOR}
RUN ./bun--setup.sh    ${CB_BUN_VERSION}
RUN ./deno--setup.sh   ${CB_DENO_VERSION}

RUN if [[ "$CB_HAS_VSCODE"  != false ]]; then ./react-code-extension--setup.sh ; fi
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then ./jetbrains--setup.sh webstorm   ; fi

WORKDIR /home/coder/code
