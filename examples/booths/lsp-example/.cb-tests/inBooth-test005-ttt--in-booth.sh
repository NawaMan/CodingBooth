#!/bin/bash
# TTT, the default editor, is pointed at every installed server at container start.
set -euo pipefail
conf="$HOME/.config/ttt/settings.json"
fail=0
[[ "$(readlink -f /usr/local/bin/editor)" == "/opt/ttt/ttt" ]] \
  && echo "✓ editor -> ttt" || { echo "✘ editor is not ttt"; fail=1; }
for pair in markdown:marksman toml:taplo yaml:yaml-language-server bash:bash-language-server typescript:typescript-language-server; do
  key="${pair%%:*}"; server="${pair##*:}"
  if [[ "$(jq -r --arg k "$key" '.lsp.servers[$k].command[0] // empty' "$conf" 2>/dev/null)" == "$server" ]]; then
    echo "✓ ttt ${key}: ${server}"
  else
    echo "✘ ttt ${key}: no ${server} in ${conf}"
    fail=1
  fi
done
exit "$fail"
