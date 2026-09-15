# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Build the CLI binary inside a booth
build-cli:
    booth -- ./build/cli-build.sh

# Build the Docker images
build-docker:
    ./build/docker-build.sh

# Build the CLI and Docker images
build-all:
    ./build/build-all.sh

# Run the automated test suites
run-tests:
    ./tests/run-automate-tests.sh

# Refresh example booth scripts, then run the workspace example tests
run-examples:
    cd examples && ./update-booth.sh && cd workspaces && ./run-example-tests.sh
