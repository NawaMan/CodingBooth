# syntax=docker/dockerfile:1.7
# Test Dockerfile for cb-home feature (override)

ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

# Copy and run the test setup script
COPY setups/test-home-override--setup.sh /opt/codingbooth/setups/
RUN chmod +x /opt/codingbooth/setups/test-home-override--setup.sh \
 && /opt/codingbooth/setups/test-home-override--setup.sh

WORKDIR /home/coder/code
