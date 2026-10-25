#!/bin/bash
echo "=== Testing the leanblueprint command itself (leanblueprint all) ==="
# leanblueprint needs the project's git repository. This example is a subfolder of the
# CodingBooth repository, so run it on a copy that is its own repository.
cd "$(dirname "$0")/.."
work="$(mktemp -d)/odd-squares"
mkdir -p "$work"
cp -r OddSquares OddSquares.lean lakefile.toml lake-manifest.json lean-toolchain blueprint .lake "$work"/
rm -rf "$work"/blueprint/web "$work"/blueprint/print "$work"/blueprint/lean_decls
cd "$work" && git init -q
if ! leanblueprint all >/tmp/bp-cli.out 2>&1; then
    echo "  ✗ leanblueprint all failed:"; tail -30 /tmp/bp-cli.out; exit 1
fi
[[ -s blueprint/print/print.pdf && -s blueprint/web/index.html ]] \
    || { echo "  ✗ leanblueprint all produced no PDF or web version"; exit 1; }
echo "  ✓ leanblueprint all: PDF, web, lake build, checkdecls"
