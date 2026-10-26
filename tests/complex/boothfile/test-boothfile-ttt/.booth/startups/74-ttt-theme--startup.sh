#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant base --select ttt/lsp

# Seed the TTT theme and border style where settings.json has none yet.
conf="${HOME}/.config/ttt/settings.json"
mkdir -p "$(dirname "$conf")"
[[ -s "$conf" ]] || echo '{"version":1}' > "$conf"
tmp="$(mktemp)"
if jq --arg theme "${TTT_THEME:-zenith}" --arg border "${TTT_BORDER_STYLE:-rounded}" \
     '.theme //= $theme | .editor.borderStyle //= $border' "$conf" > "$tmp"; then
  mv "$tmp" "$conf"
else
  rm -f "$tmp"
  echo "⚠️  TTT theme was not set; ${conf} is not JSON." >&2
fi
