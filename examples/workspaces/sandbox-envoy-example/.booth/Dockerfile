# syntax=docker/dockerfile:1.7
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG BOOTH_SETUPS=/opt/codingbooth/setups
WORKDIR /opt/codingbooth/setups

# Keep this example minimal; sandbox sidecars handle proxy/firewall.
RUN ./claude-code--setup.sh || true

WORKDIR /home/coder/code
