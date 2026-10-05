# syntax=docker/dockerfile:1.7
# Test Dockerfile for fine-grained cb-home-seed/cb-home copy

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

# Copy and run the test setup script
COPY setups/test-fine-grained--setup.sh /opt/codingbooth/setups/
RUN chmod +x /opt/codingbooth/setups/test-fine-grained--setup.sh \
 && /opt/codingbooth/setups/test-fine-grained--setup.sh

WORKDIR /home/coder/code
