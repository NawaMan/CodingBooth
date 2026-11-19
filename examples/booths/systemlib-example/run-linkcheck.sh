#!/bin/bash
# Alias kept for the docs and tests — builds and runs the link checker.
# The work lives in build.sh (configure + compile) and run.sh (build + run).
exec "$(dirname "$0")/run.sh" "$@"
