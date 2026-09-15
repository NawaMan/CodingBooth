# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
    @just --list

# Build the CLI binary inside a booth
build-cli:
    ./booth -- ./build/cli-build.sh

# Build the Docker images
build-docker:
    ./build/docker-build.sh

# Build the CLI and Docker images
build-all:
    ./booth -- ./build/cli-build.sh
    ./build/docker-build.sh

# Run the automated test suites
run-tests:
    ./tests/run-automate-tests.sh

# Refresh example booth scripts, then run the workspace example tests
run-examples:
    ./examples/update-booth.sh
    ./examples/workspaces/run-example-tests.sh

# Build everything, then run the automated tests and the example tests
verify: build-all run-tests run-examples
