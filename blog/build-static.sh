#!/usr/bin/env bash
#
# build-static.sh — build GeekPresent as a self-contained static site into a
# folder of your choice (independent of the docs/ + GitHub Pages flow).
#
# Usage:
#   ./build-static.sh <output-dir> [route]
#
#   <output-dir>   (required) where to write the static site. Created if missing.
#                  If it already exists it must be empty or a previous output of
#                  this script (use --force to overwrite anything else).
#   [route]        (optional) build only ONE presentation/text instead of the
#                  whole site. Use the route name as it appears in the URL, e.g.
#                  geeklight, slides, portrait, text.html. Omit to build the
#                  whole site (the home/landing page and every presentation).
#
# Examples:
#   ./build-static.sh ./dist                 # whole site            -> ./dist
#   ./build-static.sh /tmp/out geeklight     # just the geeklight deck -> /tmp/out
#   ./build-static.sh ./out text.html        # just the text sample  -> ./out
#   ./build-static.sh --force ./dist         # overwrite a non-empty ./dist
#   ./build-static.sh --zip ./dist           # also produce ./dist.zip
#
# Flags:
#   --force         overwrite a non-empty output dir not created by this script.
#   --precompress   also emit .br/.gz next to each asset (off by default). Only
#                   useful if your host serves precompressed files directly
#                   (nginx gzip_static, Caddy, …); otherwise they're dead weight.
#   --zip           after building, package the output into <output-dir>.zip.
#   -h, --help      show this help and exit.
#
# The result is fully portable: assets use relative paths, so you can serve it
# from any folder, any sub-path, or any static host. Just open index.html.

set -euo pipefail

MARKER=".geekpresent-static"   # dropped in outputs we own, so rebuilds are safe to wipe

usage() {
	cat <<'EOF'
build-static.sh — build GeekPresent as a self-contained static site into a
folder of your choice (independent of the docs/ + GitHub Pages flow).

Usage:
  ./build-static.sh [flags] <output-dir> [route]

Arguments:
  <output-dir>   (required) where to write the static site. Created if missing.
                 If it already exists it must be empty or a previous output of
                 this script (use --force to overwrite anything else).
  [route]        (optional) build only ONE presentation/text instead of the
                 whole site. Use the route name as it appears in the URL, e.g.
                 geeklight, slides, portrait, text.html. Omit to build the
                 whole site (the home/landing page and every presentation).

Flags:
  --force         overwrite a non-empty output dir not created by this script.
  --precompress   also emit .br/.gz next to each asset (off by default). Only
                  useful if your host serves precompressed files directly
                  (nginx gzip_static, Caddy, …); otherwise they're dead weight.
  --zip           after building, package the output into <output-dir>.zip.
  -h, --help      show this help and exit.

Examples:
  ./build-static.sh ./dist                 # whole site            -> ./dist
  ./build-static.sh /tmp/out geeklight     # just the geeklight deck -> /tmp/out
  ./build-static.sh ./out text.html        # just the text sample  -> ./out
  ./build-static.sh --force ./dist         # overwrite a non-empty ./dist
  ./build-static.sh --zip ./dist           # also produce ./dist.zip
EOF
}

# --- parse args -------------------------------------------------------------
FORCE=0
PRECOMPRESS=0
ZIP=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--force|-f)    FORCE=1 ;;
		--precompress) PRECOMPRESS=1 ;;
		--zip)         ZIP=1 ;;
		-h|--help)     usage; exit 0 ;;
		-*)            echo "error: unknown flag '$a'" >&2; echo >&2; usage >&2; exit 1 ;;
		*)             ARGS+=("$a") ;;
	esac
done

export GEEKPRESENT_PRECOMPRESS="$PRECOMPRESS"

OUT="${ARGS[0]:-}"
ROUTE="${ARGS[1]:-}"
if [ -z "$OUT" ]; then
	echo "error: missing <output-dir>" >&2
	echo >&2
	usage >&2
	exit 1
fi

# --- resolve paths ----------------------------------------------------------
START_PWD="$PWD"
ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$OUT" in
	/*) ;;                       # already absolute
	*)  OUT="$START_PWD/$OUT" ;; # relative to where the user invoked us
esac

cd "$ROOT"

# --- pick a package manager -------------------------------------------------
if command -v pnpm >/dev/null 2>&1; then
	PM="pnpm"
elif command -v npm >/dev/null 2>&1; then
	PM="npm run"
else
	echo "error: need pnpm (preferred) or npm on PATH" >&2
	exit 1
fi

# Fail fast before a long build if --zip can't be honoured.
if [ "$ZIP" = "1" ] && ! command -v zip >/dev/null 2>&1; then
	echo "error: --zip needs the 'zip' command on PATH" >&2
	exit 1
fi

# --- finalize: marker, optional zip, done message ---------------------------
finalize() {
	touch "$OUT/$MARKER"
	if [ "$ZIP" = "1" ]; then
		local parent base zipfile
		parent="$(dirname "$OUT")"
		base="$(basename "$OUT")"
		zipfile="$OUT.zip"
		rm -f "$zipfile"
		# Archive the folder itself (so it extracts into <base>/), minus our marker.
		( cd "$parent" && zip -rq "$base.zip" "$base" -x "$base/$MARKER" )
		echo ">> zipped -> $zipfile"
	fi
	echo ">> done. open: $OUT/index.html"
}

# --- guard the output dir ---------------------------------------------------
ensure_out_safe() {
	if [ -e "$OUT" ] && [ ! -d "$OUT" ]; then
		echo "error: $OUT exists and is not a directory" >&2
		exit 1
	fi
	if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
		if [ -f "$OUT/$MARKER" ] || [ "$FORCE" = "1" ]; then
			rm -rf "${OUT:?}"/* "${OUT:?}"/.[!.]* 2>/dev/null || true
		else
			echo "error: $OUT is not empty and was not created by this script." >&2
			echo "       Remove it, pick another folder, or pass --force." >&2
			exit 1
		fi
	fi
	mkdir -p "$OUT"
}

# --- build ------------------------------------------------------------------
if [ -z "$ROUTE" ]; then
	# Whole site: build straight into the output dir (adapter-static wipes &
	# fills it). docs/ is never touched.
	ensure_out_safe
	echo ">> building whole site -> $OUT"
	GEEKPRESENT_OUT="$OUT" $PM build
	finalize
	exit 0
fi

# Single presentation/text: build into a temp dir, then copy out just the
# shared runtime + that route, plus a redirecting index.html at the root.
ensure_out_safe
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo ">> building (full prerender, will extract '$ROUTE') ..."
GEEKPRESENT_OUT="$TMP" $PM build

# Validate the requested route actually produced output.
if [ ! -d "$TMP/$ROUTE" ] && [ ! -f "$TMP/$ROUTE" ]; then
	echo "error: no build output for route '$ROUTE'." >&2
	echo "       Available routes:" >&2
	( cd "$TMP" && find . -maxdepth 1 -mindepth 1 \
		\( -type d -o -name '*.html' \) -not -name '_app' \
		-not -name 'article.html' -not -name 'index.html' \
		| sed 's|^\./|         |' ) >&2
	exit 1
fi

echo ">> assembling '$ROUTE' -> $OUT"

# Shared runtime + site-wide assets the route depends on.
cp -a "$TMP/_app"          "$OUT/"
cp -a "$TMP/article.html"  "$OUT/" 2>/dev/null || true   # SPA fallback
[ -e "$TMP/fonts" ]        && cp -a "$TMP/fonts"       "$OUT/"
[ -e "$TMP/favicon.png" ]  && cp -a "$TMP/favicon.png" "$OUT/"
cp -a "$TMP/.nojekyll"     "$OUT/" 2>/dev/null || true

# The route itself (a folder for a presentation, or a single file for a text).
ENTRY=""
if [ -d "$TMP/$ROUTE" ]; then
	cp -a "$TMP/$ROUTE" "$OUT/"
	if [ -f "$OUT/$ROUTE/index.html" ]; then
		ENTRY="$ROUTE/index.html"
	else
		# Prefer the first slide declared in pages.ts, else title.html, else any.
		first="$(grep -oE 'path:[[:space:]]*"[^"]+"' "src/routes/$ROUTE/pages.ts" 2>/dev/null \
			| head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
		if [ -n "$first" ] && [ -f "$OUT/$ROUTE/$first" ]; then
			ENTRY="$ROUTE/$first"
		elif [ -f "$OUT/$ROUTE/title.html" ]; then
			ENTRY="$ROUTE/title.html"
		else
			ENTRY="$(cd "$OUT" && ls "$ROUTE"/*.html 2>/dev/null | head -1)"
		fi
	fi
else
	# Single-file route, e.g. text.html (plus its precompressed siblings).
	cp -a "$TMP/$ROUTE"     "$OUT/"
	cp -a "$TMP/$ROUTE".gz  "$OUT/" 2>/dev/null || true
	cp -a "$TMP/$ROUTE".br  "$OUT/" 2>/dev/null || true
	ENTRY="$ROUTE"
fi

# Root index.html that drops the visitor onto the presentation's entry page.
if [ -n "$ENTRY" ] && [ ! -f "$OUT/index.html" ]; then
	cat > "$OUT/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=./$ENTRY">
<title>GeekPresent — $ROUTE</title>
<link rel="canonical" href="./$ENTRY">
<p>Redirecting to <a href="./$ENTRY">$ENTRY</a> …</p>
HTML
fi

finalize
