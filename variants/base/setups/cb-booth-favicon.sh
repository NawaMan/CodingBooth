#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# cb-booth-favicon.sh — pick the browser-tab icon for every booth Web UI.
#
# A project file under .booth/favicon/ wins, in this order: favicon.svg,
# favicon.png, favicon.ico. Otherwise the built-in mark is used
# (docs/favicon.png, installed at /usr/local/share/codingbooth/favicon.png).
#
# Writes three things into <out-dir>, which nginx then serves:
#   link                one <link rel="icon"> element (may be empty)
#   locations           nginx server-context locations (may be empty)
#   favicon.<ext>       the bytes to serve
#
# /favicon.ico is claimed here on purpose. With no exact location, the
# console rewrites that automatic browser request into index.html, and a
# wrapped variant proxies it to the inner app, whose icon then takes the tab.
# An .ico project file is served at that path. An svg or png answers 204 so
# the <link> is the only icon the browser keeps.
#
# SVG is served with a sandbox CSP. Opening the icon URL as a document must
# not run script on the booth origin.
#
# Usage: cb-booth-favicon.sh <out-dir>
#   CB_FAVICON_DIR       default /home/coder/code/.booth/favicon
#   CB_FAVICON_DEFAULT   default /usr/local/share/codingbooth/favicon.png
#   CB_FAVICON_MAX_BYTES default 262144

set -euo pipefail

OUT="${1:?usage: cb-booth-favicon.sh <out-dir>}"
DIR="${CB_FAVICON_DIR:-/home/coder/code/.booth/favicon}"
DEFAULT="${CB_FAVICON_DEFAULT:-/usr/local/share/codingbooth/favicon.png}"
MAX="${CB_FAVICON_MAX_BYTES:-262144}"

mkdir -p "$OUT"
rm -f "$OUT/favicon.svg" "$OUT/favicon.png" "$OUT/favicon.ico"

pick=""
ext=""

consider() {
  local path="$1" e="$2" sz
  [[ -z "$pick" ]] || return 0
  [[ -f "$path" && ! -L "$path" ]] || return 0
  sz=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path")
  if (( sz == 0 || sz > MAX )); then
    echo "cb-booth-favicon: skipping ${path} (${sz} bytes)" >&2
    return 0
  fi
  pick="$path"
  ext="$e"
}

consider "${DIR}/favicon.svg" svg
consider "${DIR}/favicon.png" png
consider "${DIR}/favicon.ico" ico

if [[ -z "$pick" && -f "$DEFAULT" && ! -L "$DEFAULT" ]]; then
  pick="$DEFAULT"
  ext="png"
fi

if [[ -z "$pick" ]]; then
  echo "cb-booth-favicon: no icon found" >&2
  : >"$OUT/link"
  : >"$OUT/locations"
  exit 0
fi

cp -f "$pick" "$OUT/favicon.${ext}"
chmod 0644 "$OUT/favicon.${ext}"

hash=$(sha256sum "$OUT/favicon.${ext}" | awk '{print substr($1,1,12)}')

case "$ext" in
  svg) mime="image/svg+xml" ;;
  png) mime="image/png" ;;
  ico) mime="image/x-icon" ;;
esac

printf '<link rel="icon" type="%s" href="/booth-assets/favicon.%s?v=%s">' \
  "$mime" "$ext" "$hash" >"$OUT/link"

{
  echo "        location = /booth-assets/favicon.${ext} {"
  echo "            alias ${OUT}/favicon.${ext};"
  echo "            default_type ${mime};"
  echo "            add_header X-Content-Type-Options nosniff always;"
  if [[ "$ext" == "svg" ]]; then
    echo "            add_header Content-Security-Policy \"default-src 'none'; style-src 'unsafe-inline'; sandbox\" always;"
  fi
  echo "            add_header Cache-Control \"public, max-age=86400\" always;"
  echo "        }"
  echo ""
  if [[ "$ext" == "ico" ]]; then
    echo "        location = /favicon.ico {"
    echo "            alias ${OUT}/favicon.ico;"
    echo "            default_type image/x-icon;"
    echo "            add_header X-Content-Type-Options nosniff always;"
    echo "            add_header Cache-Control \"public, max-age=86400\" always;"
    echo "        }"
  else
    echo "        location = /favicon.ico {"
    echo "            access_log off;"
    echo "            return 204;"
    echo "        }"
  fi
} >"$OUT/locations"

echo "cb-booth-favicon: ${pick}" >&2
