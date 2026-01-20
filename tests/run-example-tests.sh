#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Wrapper script to run all example workspace tests
# Calls examples/workspaces/run-all-example-tests.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/../examples/workspaces"

exec "$EXAMPLES_DIR/run-all-example-tests.sh"
