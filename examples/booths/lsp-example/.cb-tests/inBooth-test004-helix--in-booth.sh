#!/bin/bash
# Helix starts the servers by their default names, with no config at all.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for pair in markdown:marksman toml:taplo yaml:yaml-language-server bash:bash-language-server typescript:typescript-language-server; do
  lang="${pair%%:*}"; server="${pair##*:}"
  if just helix "$lang" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "✓ ${server}:"; then
    echo "✓ helix ${lang}: ${server}"
  else
    echo "✘ helix ${lang}: ${server} not found"
    fail=1
  fi
done
exit "$fail"
