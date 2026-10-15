#!/bin/bash
# The base image links Fresh's booth-lsp plugin at container start.
set -euo pipefail
link="$HOME/.config/fresh/plugins/booth-lsp.ts"
target="$(readlink "$link" || true)"
if [[ "$target" == "/opt/codingbooth/setups/fresh-plugins/booth-lsp.ts" && -r "$target" ]]; then
  echo "✓ ${link} -> ${target}"
else
  echo "✘ ${link} is not linked to the booth-lsp plugin (got '${target}')"
  exit 1
fi
