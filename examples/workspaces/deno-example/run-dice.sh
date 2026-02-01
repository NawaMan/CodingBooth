#!/bin/bash
# Run the dice roller
cd "$(dirname "$0")"
deno run src/dice.ts "$@"
