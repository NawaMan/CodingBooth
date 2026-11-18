#!/bin/bash
# Run Prime number generator
cd "$(dirname "$0")"
zig build run -- "$@"
