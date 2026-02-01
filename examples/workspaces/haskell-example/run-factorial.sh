#!/bin/bash
# Run Factorial calculator
cd "$(dirname "$0")"
runghc src/Factorial.hs "$@"
