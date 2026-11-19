#!/bin/bash
# Run the greeter
cd "$(dirname "$0")"
bun run src/greeter.ts "$@"
