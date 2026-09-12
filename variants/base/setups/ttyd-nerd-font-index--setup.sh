#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ttyd-nerd-font-index--setup.sh — bakes a custom ttyd index.html that embeds
# the Fira Code Nerd Font Mono (regular + bold) as inline @font-face data URIs.
# Embeds the .woff2 fira-code-nerd-font--setup.sh generates, not the .ttf it
# installs for native apps — WOFF2's font-specific compression roughly halves
# the bytes, which halves this page's size too.
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

REGULAR_WOFF2="${FONT_DIR}/FiraCodeNerdFontMono-Regular.woff2"
BOLD_WOFF2="${FONT_DIR}/FiraCodeNerdFontMono-Bold.woff2"
for f in "$REGULAR_WOFF2" "$BOLD_WOFF2"; do
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
REGULAR_B64="$(base64 -w0 "$REGULAR_WOFF2")"
BOLD_B64="$(base64 -w0 "$BOLD_WOFF2")"

STYLE="<style>"
STYLE+="@font-face{font-family:FiraCode Nerd Font Mono;font-weight:400;font-style:normal;font-display:swap;src:url(data:font/woff2;base64,${REGULAR_B64}) format(\"woff2\");}"
STYLE+="@font-face{font-family:FiraCode Nerd Font Mono;font-weight:700;font-style:normal;font-display:swap;src:url(data:font/woff2;base64,${BOLD_B64}) format(\"woff2\");}"
STYLE+="</style>"
# ttyd's bundled xterm.js measures its cell width once, synchronously, against
# whatever font is actually rendering at that instant — usually the browser's
# fallback monospace, since the @font-face above hasn't finished decoding yet.
# It never re-measures once the real font takes over, so every cell stays
# sized for the fallback's (wider) advance width and the narrower Nerd Font
# glyphs render with a gap between them.
#
# Calling xterm's own _charSizeService.measure() directly to force a
# correction — tried twice, once as a single attempt and once debounced on
# xterm's onRender going quiet — corrupted the terminal (blank rows, or a
# stuck resize) whenever it landed while a reattached tmux pane was replaying
# its buffer, reproduced live against this exact page. A JS-triggered
# location.reload() was tried next, on the theory that a manual hard refresh
# always fixes this; it doesn't reliably — the reloaded page can lose the
# same race again, and a reload has no in-place retry.
#
# This instead dispatches a plain resize event, which drives ttyd's own
# window-resize handler — the same code path every browser window resize
# already exercises, so it's expected to handle a concurrent tmux replay
# correctly. The mismatch check itself never touches xterm's internals: it
# independently measures the loaded font with a throwaway canvas context
# (zero side effects) and compares that to xterm's cached cell width, only
# dispatching the resize when they actually disagree.
STYLE+='<script>document.fonts.ready.then(function(){var checks=0;function check(){checks++;var t=window.term,s=t&&t._core&&t._core._charSizeService;if(s){try{var c=document.createElement("canvas").getContext("2d");c.font=(t.options.fontSize||15)+"px "+t.options.fontFamily;var want=c.measureText("W").width;if(Math.abs(s.width-want)>2){window.dispatchEvent(new Event("resize"));}}catch(e){}}if(checks<30){setTimeout(check,500);}}check();});</script>'

DEFAULT_HTML_CONTENT="$(cat "$DEFAULT_HTML")"
printf '%s' "${DEFAULT_HTML_CONTENT/<head>/<head>$STYLE}" > "$OUT"
rm -f "$DEFAULT_HTML"

if ! grep -q "FiraCode Nerd Font Mono" "$OUT"; then
  echo "❌ Failed to splice the font into ttyd's index.html" >&2
  rm -f "$OUT"
  exit 1
fi

echo "✅ Custom ttyd index with embedded Fira Code Nerd Font Mono written to $OUT ($(du -h "$OUT" | cut -f1))"
