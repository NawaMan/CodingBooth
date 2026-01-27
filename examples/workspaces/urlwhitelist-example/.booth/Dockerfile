# syntax=docker/dockerfile:1.7
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/codingbooth/setups
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest

# Setup
WORKDIR /opt/codingbooth/setups

# Copy the modified setup script (local override until base image is updated)
COPY setups/network-whitelist--setup.sh ./network-whitelist--setup.sh

# Install network whitelist - restricts internet access to whitelisted domains
RUN ./network-whitelist--setup.sh

# Always install claude-code
RUN ./claude-code--setup.sh
RUN ./antigravity--setup.sh

WORKDIR /home/coder/code
