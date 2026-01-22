# syntax=docker/dockerfile:1.7
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/coding-booth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/coding-booth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
ARG CB_HAS_NOTEBOOK=false
ARG CB_HAS_VSCODE=false
ARG CB_HAS_DESKTOP=false

# Setup
WORKDIR /opt/coding-booth/setups

# Install network whitelist - restricts internet access to whitelisted domains
RUN ./network-whitelist--setup.sh

# Always install claude-code
RUN ./claude-code--setup.sh
RUN if [[ "$CB_HAS_DESKTOP" != false ]]; then ./antigravity--setup.sh ; fi

WORKDIR /home/coder/code
