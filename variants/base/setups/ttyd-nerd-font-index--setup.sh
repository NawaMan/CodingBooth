#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ttyd-nerd-font-index--setup.sh — bakes a custom ttyd index.html that embeds
# the Fira Code Nerd Font Mono (regular + bold) as inline @font-face data URIs.
#
# ttyd's terminal renders in the *visitor's browser* via canvas/WebGL, not in
# this container, so installing the font system-wide
# (fira-code-nerd-font--setup.sh) has no effect on what actually gets drawn —
# the `-t fontFamily=...` client option only *names* a font, it doesn't supply
# one. start-ttyd-split solves this with an nginx `sub_filter` that injects a
# <style> referencing the font as a real, cacheable asset shared by all 4
# panes. The non-split fallback (BOOTH_WEB_SPLIT=false) has no nginx in front
# of it — ttyd listens directly — so there's nothing to inject into. Instead,
# this script captures ttyd's own bundled index.html (a single self-contained
# file with no external asset references — confirmed by inspecting a live
# instance) and splices the font directly in as data URIs, then start-ttyd
# hands the result to `ttyd -I`.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

FONT_DIR="/usr/share/fonts/truetype/fira-code-nerd-font"
OUT="/usr/local/share/ttyd-nerd-font-index.html"

if [[ -f "$OUT" ]]; then
  echo "ℹ️  $OUT already generated"
  exit 0
fi

REGULAR_TTF="${FONT_DIR}/FiraCodeNerdFontMono-Regular.ttf"
BOLD_TTF="${FONT_DIR}/FiraCodeNerdFontMono-Bold.ttf"
for f in "$REGULAR_TTF" "$BOLD_TTF"; do
  [[ -f "$f" ]] || { echo "❌ Missing $f — run fira-code-nerd-font--setup.sh first" >&2; exit 1; }
done

command -v ttyd  >/dev/null 2>&1 || { echo "❌ ttyd not installed" >&2; exit 1; }
command -v curl  >/dev/null 2>&1 || { echo "❌ curl not installed" >&2; exit 1; }

# ---- capture ttyd's own bundled index.html from a throwaway instance ----
CAPTURE_PORT=57681
DEFAULT_HTML="$(mktemp)"
ttyd -p "$CAPTURE_PORT" true &
TTYD_PID=$!
FETCHED=false
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${CAPTURE_PORT}/" -o "$DEFAULT_HTML" 2>/dev/null && [[ -s "$DEFAULT_HTML" ]]; then
    FETCHED=true
    break
  fi
  sleep 0.25
done
kill "$TTYD_PID" 2>/dev/null || true
wait "$TTYD_PID" 2>/dev/null || true

if [[ "$FETCHED" != true ]]; then
  echo "❌ Could not fetch ttyd's default index.html" >&2
  rm -f "$DEFAULT_HTML"
  exit 1
fi

if ! grep -q '<head>' "$DEFAULT_HTML"; then
  echo "❌ ttyd's default index.html has no <head> tag to splice into" >&2
  rm -f "$DEFAULT_HTML"
  exit 1
fi

# ---- splice the @font-face style right after the opening <head> tag ----
REGULAR_B64="$(base64 -w0 "$REGULAR_TTF")"
BOLD_B64="$(base64 -w0 "$BOLD_TTF")"

STYLE="<style>"
STYLE+="@font-face{font-family:FiraCode Nerd Font Mono;font-weight:400;font-style:normal;font-display:swap;src:url(data:font/ttf;base64,${REGULAR_B64});}"
STYLE+="@font-face{font-family:FiraCode Nerd Font Mono;font-weight:700;font-style:normal;font-display:swap;src:url(data:font/ttf;base64,${BOLD_B64});}"
STYLE+="</style>"

DEFAULT_HTML_CONTENT="$(cat "$DEFAULT_HTML")"
printf '%s' "${DEFAULT_HTML_CONTENT/<head>/<head>$STYLE}" > "$OUT"
rm -f "$DEFAULT_HTML"

if ! grep -q "FiraCode Nerd Font Mono" "$OUT"; then
  echo "❌ Failed to splice the font into ttyd's index.html" >&2
  rm -f "$OUT"
  exit 1
fi

echo "✅ Custom ttyd index with embedded Fira Code Nerd Font Mono written to $OUT ($(du -h "$OUT" | cut -f1))"
