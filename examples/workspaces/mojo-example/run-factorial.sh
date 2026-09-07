#!/bin/bash
# Run Factorial calculator
cd "$(dirname "$0")"
mojo src/factorial.mojo "$@"
