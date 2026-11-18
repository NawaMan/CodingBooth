#!/bin/bash
# Run Factorial calculator
cd "$(dirname "$0")"
runghc Factorial.hs "$@"
