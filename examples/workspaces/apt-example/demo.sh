#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Put each apt-installed tool to work on this example's own files: jq reads a
# bit of JSON, tree draws .booth/, rg searches the Boothfile. Then show which
# archive they came from (./versions.sh).
set -euo pipefail

cd "$(dirname "$0")"

echo "=== jq: pick fields out of JSON ==="
echo '{"packages":[{"name":"jq"},{"name":"tree"},{"name":"ripgrep","binary":"rg"}]}' \
  | jq -r '.packages[] | "\(.name) -> \(.binary // .name)"'
echo

echo "=== tree: this booth's config ==="
tree -a --noreport .booth
echo

echo "=== rg: where the Boothfile pins apt ==="
rg --line-number --color never 'APT_' .booth/Boothfile
echo

echo "=== The archive these came from ==="
./versions.sh
