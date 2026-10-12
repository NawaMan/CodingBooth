#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant base --select fresh

# Apply the selected Fresh theme. Other keys in the user config stay.
theme="${FRESH_THEME:-terminal}"
conf="${HOME}/.config/fresh/config.json"
mkdir -p "$(dirname "$conf")"
if [[ ! -s "$conf" ]]; then
  jq -n --arg theme "$theme" '{version:1, theme:$theme}' > "$conf"
else
  tmp="$(mktemp)"
  if jq --arg theme "$theme" '.theme = $theme' "$conf" > "$tmp"; then
    mv "$tmp" "$conf"
  else
    rm -f "$tmp"
    echo "⚠️  Fresh theme was not set; ${conf} is not JSON." >&2
  fi
fi
