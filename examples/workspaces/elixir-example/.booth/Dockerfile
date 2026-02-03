# syntax=docker/dockerfile:1.7
# Elixir Example Dockerfile
# Uses apt packages for simplicity (faster than building from source)

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

# Install Erlang and Elixir from apt (simpler than kerl for examples)
RUN apt-get update && \
    apt-get install -y --no-install-recommends erlang elixir && \
    rm -rf /var/lib/apt/lists/* && \
    mix local.hex --force && \
    mix local.rebar --force
