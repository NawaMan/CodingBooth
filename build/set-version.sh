#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# set-version.sh - Set the project version in version.txt and README.md
#
# Usage: ./set-version.sh <version>
#   <version> must match  #.#.#  optionally followed by  --rc#
#   (where # is one or more digits), e.g. 0.54.0  or  0.54.0--rc1
#
set -euo pipefail

# Resolve repo root from this script's location (build/..) so it works from any CWD.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/version.txt"
README_FILE="$ROOT/README.md"

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(--rc[0-9]+)?$'

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <version>" >&2
  echo "  e.g. $(basename "$0") 0.54.0" >&2
  echo "       $(basename "$0") 0.54.0--rc1" >&2
  exit 2
fi

VERSION="$1"

if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "ERROR: invalid version: '$VERSION'" >&2
  echo "  Expected #.#.# optionally followed by --rc# (e.g. 0.54.0 or 0.54.0--rc1)" >&2
  exit 1
fi

for f in "$VERSION_FILE" "$README_FILE"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: not found: $f" >&2
    exit 1
  fi
done

# README.md must carry the "**Current Version:** v..." marker the hook checks.
if ! grep -q '\*\*Current Version:\*\* v' "$README_FILE"; then
  echo "ERROR: '**Current Version:** v...' line not found in $README_FILE" >&2
  exit 1
fi

# version.txt: bare version, trailing newline (matches existing format).
printf '%s\n' "$VERSION" > "$VERSION_FILE"

# README.md: replace only the version token after the 'v', preserve the rest
# of the line (e.g. the " — [View Changelog](...)" suffix). Write via temp file
# so it is portable across BSD (macOS) and GNU sed.
tmp="$(mktemp)"
sed "s|\(\*\*Current Version:\*\* v\)[^ ]*|\1${VERSION}|" "$README_FILE" > "$tmp"
mv "$tmp" "$README_FILE"

echo "Version set to $VERSION"
echo "  $VERSION_FILE"
echo "  $README_FILE"
