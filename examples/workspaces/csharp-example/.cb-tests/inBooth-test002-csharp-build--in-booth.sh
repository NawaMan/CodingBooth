#!/bin/bash
# Test: C# project builds and runs
echo "=== Testing C# build and run ==="
# bin/ and obj/ are checked into git with an x86_64 apphost; on arm64 hosts
# `dotnet run` would reuse the stale binary and fail with a rosetta/elf
# loader error. Clear them so the build always emits arch-correct output.
rm -rf bin obj
dotnet run --project .
