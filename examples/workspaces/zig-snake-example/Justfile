run := if env("BOOTH_CONTAINER_NAME", "") == "" { "./booth exec --run --" } else { "" }

[private]
default:
    @just --list

# Cross-compile native binaries for six targets into dist/
build:
    {{run}} ./build-all.sh

# Build and play Snake in the terminal
run:
    {{run}} zig build run
