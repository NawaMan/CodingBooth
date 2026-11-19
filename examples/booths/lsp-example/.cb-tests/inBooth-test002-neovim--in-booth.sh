#!/bin/bash
# neovim+lsp's booth-lsp.lua must attach the servers without any user config.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for pair in "docs/guide.md:marksman" "settings.toml:taplo" "deploy.yaml:yamlls" "scripts/greet.sh:bashls" "src/greet.ts:ts_ls"; do
  file="${pair%%:*}"; want="${pair##*:}"
  got="$(just nvim "$file" 2>/dev/null | tail -1)"
  if [[ ",${got#*: }," == *"${want}"* ]]; then
    echo "✓ ${file}: ${got}"
  else
    echo "✘ ${file}: expected ${want}, got '${got}'"
    fail=1
  fi
done
exit "$fail"
