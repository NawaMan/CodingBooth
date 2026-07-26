#!/usr/bin/env bash
#
# capture-slides.sh — render every slide of a built deck to a PNG.
#
# The offline counterpart to the in-app CAPTURE button. Same idea (a slide has a TRUE
# size, so a screenshot should be the canvas, not somebody's window), different engine:
# CAPTURE rasterises the DOM itself through an SVG <foreignObject>, which cannot draw a
# live <iframe>; this drives a real browser, so it captures EVERYTHING — embeds, video,
# Monaco code blocks, the lot. It is the right tool for OG/social images and thumbnails.
#
# The whole trick is the `?shot` flag, which tells SlideDeck to render the canvas at
# exactly 1:1 with no frame, no chrome and no letterbox. Size the browser window to the
# canvas and the viewport IS the slide, so the PNG needs no cropping and no rescaling.
#
# No dependencies: a static server (python3) and whatever Chrome you already have. In
# particular NOT Playwright/Puppeteer — this is a screenshot, not a test harness.
#
# Usage:
#   utils/capture-slides.sh [options]
#
#   --site <dir>     built site to serve            (default: docs)
#   --deck <name>    deck folder inside the site    (default: slides)
#   --out <dir>      where the PNGs land            (default: captures/<deck>)
#   --size <WxH>     canvas size                    (default: 1920x1080)
#   --scale <f>      device scale factor            (default: 1; 2 → a 2x PNG)
#   --port <n>       port for the local server      (default: 8123)
#   --slide <file>   capture just this one (e.g. title.html); repeatable
#
#   --og             SOCIAL CARDS. Capture into static/og/<deck>/ (gitignored; regenerated
#                    in CI before the build), then wire each PNG into the deck's pages.ts
#                    `image:` field, so every slide's OG/Twitter card IS THAT SLIDE instead
#                    of the site default. Opt-in, and it EDITS SOURCE (pages.ts) — the edit
#                    is idempotent, it never overwrites an `image` an author already set,
#                    and `git diff` shows you exactly which slides got a card.
#   --no-wire        with --og: write the PNGs but don't touch pages.ts.
#
# Examples:
#   pnpm build && utils/capture-slides.sh
#   pnpm build && utils/capture-slides.sh --og      # social cards, wired into pages.ts
#   utils/capture-slides.sh --deck portrait --size 1080x1920
#   utils/capture-slides.sh --slide title.html --out /tmp
set -euo pipefail

SITE="docs"; DECK="slides"; OUT=""; SIZE="1920x1080"; PORT="8123"; SCALE=""; OG=0; WIRE=1; ONLY=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--site)  SITE="$2";  shift 2 ;;
		--deck)  DECK="$2";  shift 2 ;;
		--out)   OUT="$2";   shift 2 ;;
		--size)  SIZE="$2";  shift 2 ;;
		--scale) SCALE="$2"; shift 2 ;;
		--port)  PORT="$2";  shift 2 ;;
		--slide) ONLY+=("$2"); shift 2 ;;
		--og)      OG=1;     shift ;;
		--no-wire) WIRE=0;   shift ;;
		-h|--help) sed -n '2,42p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

W="${SIZE%x*}"; H="${SIZE#*x}"

# --og: social cards. They land in static/, because that is the directory the build copies to
# the site root — so `static/og/slides/title.png` is served at `/og/slides/title.png`, which is
# exactly the site-relative form seo/config.resolveImage turns into an absolute og:image URL.
#
# At FULL canvas resolution, deliberately. An earlier version shrank these to ~1200px wide on
# the grounds that a folder of full-res slides would bloat the repo — but static/og is
# gitignored and regenerated in CI, so nothing is committed and that cost never existed. And
# shrinking buys nothing else: the ASPECT RATIO is the same either way (so a card crops on a
# timeline identically), the platforms accept far larger, and the only thing a smaller file
# actually changes is that it looks blurrier on a high-DPI screen. Bigger is simply better here.
#
# `--scale 0.625` still shrinks them if you want that (via --force-device-scale-factor: the
# canvas keeps laying out at its true CSS px so nothing reflows, and Chrome rasterises those px
# into a smaller bitmap). Note that shrinking the WINDOW would CROP the slide rather than scale
# it, because `?shot` is 1:1 by design.
if [[ $OG -eq 1 ]]; then
	OUT="${OUT:-static/og/$DECK}"
fi

OUT="${OUT:-captures/$DECK}"
SCALE="${SCALE:-1}"

# Find a Chrome. Any of these will do; we only ever ask it for a screenshot.
CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser; do
	if command -v "$c" >/dev/null 2>&1; then CHROME="$c"; break; fi
done
[[ -n "$CHROME" ]] || { echo "No Chrome/Chromium found on PATH." >&2; exit 1; }

DECK_DIR="$SITE/$DECK"
[[ -d "$DECK_DIR" ]] || { echo "No such deck: $DECK_DIR (did you build?)" >&2; exit 1; }

# The slide list IS the built output — every *.html in the deck folder. No pages.ts to parse
# and no list to keep in step: if it built, it gets captured.
#
# Three files in there are NOT slides and are skipped: `text.html` and `seo.html` (the deck's
# other artifacts — the long-form read and the SEO stub) and `index.html` (the deck's own
# route landing page, which redirects into the deck and has no canvas to photograph).
mapfile -t SLIDES < <(
	if [[ ${#ONLY[@]} -gt 0 ]]; then printf '%s\n' "${ONLY[@]}"
	else find "$DECK_DIR" -maxdepth 1 -name '*.html' -printf '%f\n' \
		| grep -vE '^(text|seo|index)\.html$' | sort
	fi
)
[[ ${#SLIDES[@]} -gt 0 ]] || { echo "No slides found in $DECK_DIR" >&2; exit 1; }

mkdir -p "$OUT"

# Serve the built site. It MUST be http, not file:// — SvelteKit's client is an ES
# module, and file:// blocks module scripts, so the deck would never hydrate and every
# PNG would come out an empty dark frame. (That symptom was once written off as "the deck
# doesn't render headless". It renders fine; it just needs an origin.)
python3 -m http.server "$PORT" --directory "$SITE" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
	curl -sf "http://localhost:$PORT/" >/dev/null 2>&1 && break
	sleep 0.1
done

PROFILES="$(mktemp -d)"
trap 'kill "$SERVER" 2>/dev/null || true; rm -rf "$PROFILES"' EXIT

# The slide content is mounted on hydration (`{#if initialized}`), so a screenshot taken
# before the client runs is a valid, correctly-sized, entirely EMPTY frame. Two flags stop
# that, and both are needed:
#
#   --run-all-compositor-stages-before-draw  don't shoot until the frame is fully composited
#   --virtual-time-budget                    advance the virtual clock, but only so far
#
# The budget is the one that bit: at 8s, three of the deck's 66 slides (the ones pulling
# Monaco and webfonts off a CDN) were shot mid-load and came out blank. It is a RACE, not a
# property of those slides — which is the worst kind, because a blank slide still yields a
# plausible PNG and nobody notices until it is on someone else's timeline.
BUDGET=20000
# A PNG of the un-hydrated shell is a flat fill: under ~10KB at full size. A real slide, even a
# sparse title, is 60KB+. So a suspiciously small file means we lost the race. The threshold
# has to follow the SCALE, though — an --og card is a quarter of the pixels, so a real one can
# weigh less than a full-size blank, and a fixed number would flag every good card.
MIN_BYTES="$(awk -v s="$SCALE" 'BEGIN{ m = 20000 * s * s; if (m < 5000) m = 5000; printf "%d", m }')"

echo "Capturing ${#SLIDES[@]} slide(s) from /$DECK at ${W}x${H} → $OUT/"
FAILED=0
for i in "${!SLIDES[@]}"; do
	slide="${SLIDES[$i]}"
	png="$OUT/${slide%.html}.png"

	shoot() {
		# A FRESH profile per attempt: sharing one --user-data-dir across sequential launches
		# lets a still-shutting-down Chrome race the next one.
		"$CHROME" \
			--headless --disable-gpu --no-sandbox --hide-scrollbars \
			--user-data-dir="$PROFILES/p$i-$2" \
			--window-size="$W,$H" \
			--force-device-scale-factor="$SCALE" \
			--run-all-compositor-stages-before-draw \
			--virtual-time-budget="$1" \
			--screenshot="$png" \
			"http://localhost:$PORT/$DECK/$slide?shot" >/dev/null 2>&1 || true
	}
	size() { [[ -f "$png" ]] && stat -c%s "$png" || echo 0; }

	# Shoot, CHECK, and shoot again if we lost the race. Verifying beats tuning: the budget
	# that works on an idle machine loses on a busy one (the whole deck is 66 Chrome launches
	# back to back), and no single number is right for every machine. So we don't guess a
	# number — we look at what came out, and take the picture again if it's empty.
	bytes=0
	for attempt in 1 2 3; do
		shoot $((BUDGET * attempt)) "$attempt"
		bytes="$(size)"
		[[ "$bytes" -ge "$MIN_BYTES" ]] && break
		sleep 0.5   # let the machine breathe before trying again
	done

	if [[ "$bytes" -ge "$MIN_BYTES" ]]; then
		echo "  ✔ ${slide%.html}.png"
	elif [[ "$bytes" -gt 0 ]]; then
		# Loud, never silent. A blank slide still yields a plausible PNG, and a blank OG image
		# is the sort of thing nobody notices until it's on someone else's timeline.
		echo "  ⚠ ${slide%.html}.png — only ${bytes}B after 3 tries; probably an empty frame." >&2
		FAILED=$((FAILED + 1))
	else
		echo "  ✘ $slide — no image produced" >&2
		FAILED=$((FAILED + 1))
	fi
done

echo "Done → $OUT/"
[[ $FAILED -eq 0 ]] || { echo "$FAILED slide(s) need a look." >&2; exit 1; }

# --og: point each slide's OG/Twitter card at its own PNG.
#
# Deliberately NOT run when a slide failed above (the `exit 1` guard sits between): wiring a
# pages.ts entry to a PNG that came out blank would put an empty card on someone's timeline,
# which is the one outcome worse than having no card at all.
if [[ $OG -eq 1 && $WIRE -eq 1 ]]; then
	PAGES="src/routes/$DECK/pages.ts"
	if [[ ! -f "$PAGES" ]]; then
		echo "No $PAGES to wire — PNGs written, pages.ts untouched." >&2
	else
		# The og dir as the site sees it: static/og/slides → og/slides, which is the
		# site-relative form seo/config.resolveImage makes absolute.
		OG_DIR="${OUT#static/}"
		node utils/wire-og.mjs "$PAGES" "$OG_DIR" "${SLIDES[@]}"
		echo
		echo "  Social cards are ON ($(du -sh "$OUT" 2>/dev/null | cut -f1) in $OUT/, gitignored)."
		echo "    • Rebuild before these tags mean anything: og:image is baked into each slide's"
		echo "      prerendered HTML, so the capture must be followed by a build."
		echo "    • CI already does all of this (.github/workflows/deploy-pages.yml: build →"
		echo "      capture → build), so the pages.ts edit above need NOT be committed. Commit it"
		echo "      only if you want the wiring visible in the repo; re-running is idempotent."
	fi
fi
