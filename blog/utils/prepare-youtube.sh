#!/usr/bin/env bash
#
# prepare-youtube.sh — fetch a YouTube thumbnail so a slide can use the <YouTube>
# component right away.
#
# Assets are colocated: written into the page's own folder (next to its
# +page.svelte), not into static/:
#     <name>-TN.png     the video thumbnail (PNG)
#     <name>-QR.png     a QR code linking to the video — ONLY if qrencode is installed,
#                       and no longer needed: <YouTube> encodes the watch URL itself
#                       (via $lib/components/QRCode.svelte), so the code can never drift
#                       from the video. Pass it as {qr} only to pin an existing slide's
#                       exact pixels.
#
# and it prints the import + usage snippet to drop into that page.
#
# Usage:
#     utils/prepare-youtube.sh <youtube-url-or-id> [dest-dir] [name]
#
# Examples:
#     utils/prepare-youtube.sh https://youtu.be/wJ8ucHyJuqg src/routes/slides/talk.html onerbc
#     cd src/routes/slides/talk.html && ../../../../utils/prepare-youtube.sh wJ8ucHyJuqg
#
# [dest-dir] defaults to the current directory; [name] defaults to the video id.
#
# Requires: curl, and one of: ffmpeg | gm | convert | djpeg.  (qrencode: optional.)

set -euo pipefail

die() { echo "❌ $*" >&2; exit 1; }

# --- args -----------------------------------------------------------------
[ $# -ge 1 ] || die "Usage: $(basename "$0") <youtube-url-or-id> [dest-dir] [name]"
INPUT="$1"
DEST_DIR="${2:-.}"
NAME="${3:-}"

# --- extract the 11-char video id from common URL forms or a bare id ------
extract_id() {
	local s="$1" id=""
	case "$s" in
		*youtube.com/watch*v=*) id="${s#*v=}"; id="${id%%&*}" ;;
		*youtu.be/*)            id="${s#*youtu.be/}"; id="${id%%[?&/]*}" ;;
		*youtube.com/embed/*)   id="${s#*embed/}";  id="${id%%[?&/]*}" ;;
		*youtube.com/shorts/*)  id="${s#*shorts/}"; id="${id%%[?&/]*}" ;;
		*)                      id="$s" ;;   # assume it is already a bare id
	esac
	printf '%s' "$id"
}

VID="$(extract_id "$INPUT")"
[ -n "$VID" ] || die "Could not parse a video id from: $INPUT"
case "$VID" in
	*[!A-Za-z0-9_-]* | "") die "Parsed video id looks invalid: '$VID'" ;;
esac
[ -n "$NAME" ] || NAME="$VID"
URL="https://www.youtube.com/watch?v=$VID"

# --- deps -----------------------------------------------------------------
# qrencode is no longer required: <YouTube> encodes the QR from the watch URL at
# render time. We still write the PNG when the binary happens to be around, for
# slides that were built against it.
command -v curl >/dev/null 2>&1 || die "curl is required"

mkdir -p "$DEST_DIR"
THUMB="$DEST_DIR/$NAME-TN.png"
QR="$DEST_DIR/$NAME-QR.png"

# --- 1. download the best available thumbnail -----------------------------
tmp_jpg="$(mktemp --suffix=.jpg)"
trap 'rm -f "$tmp_jpg"' EXIT

got=""
for q in maxresdefault sgp1 hqdefault; do
	code="$(curl -sL -o "$tmp_jpg" -w '%{http_code}' --max-time 20 \
		"https://img.youtube.com/vi/$VID/$q.jpg" || true)"
	if [ "$code" = "200" ] && [ -s "$tmp_jpg" ]; then got="$q"; break; fi
done
[ -n "$got" ] || die "Could not download a thumbnail for video id '$VID'"
echo "→ thumbnail: $got.jpg"

# --- 2. convert JPG -> PNG with whatever converter is present -------------
to_png() {
	local src="$1" dst="$2"
	if   command -v ffmpeg  >/dev/null 2>&1; then ffmpeg -y -loglevel error -i "$src" "$dst"
	elif command -v gm      >/dev/null 2>&1; then gm convert "$src" "$dst"
	elif command -v convert >/dev/null 2>&1; then convert "$src" "$dst"
	elif command -v djpeg   >/dev/null 2>&1 && command -v pnmtopng >/dev/null 2>&1; then
		djpeg "$src" | pnmtopng > "$dst"
	else
		return 1
	fi
}
to_png "$tmp_jpg" "$THUMB" || die "No JPG->PNG converter found (install ffmpeg, graphicsmagick, or imagemagick)"
echo "→ wrote $THUMB"

# --- 3. QR code linking to the video (optional, legacy) --------------------
if command -v qrencode >/dev/null 2>&1; then
	qrencode -o "$QR" -s 8 -m 1 "$URL"
	echo "→ wrote $QR (optional — <YouTube> encodes this itself)"
else
	echo "→ skipped the QR png (qrencode not installed; <YouTube> encodes it itself)"
fi

# --- 4. tell the user how to use it ---------------------------------------
cat <<EOF

✅ Done. Asset written next to your page. Use it like this:

    <script>
      import YouTube   from '\$lib/components/YouTube.svelte';
      import thumbnail from './$NAME-TN.png';
    </script>

    <YouTube {thumbnail} alt="..." youtubeId="$VID" width="600px" />

The QR overlay is encoded from the watch URL at render time, so it can never drift
from the video. To pin an existing slide's exact pixels instead, import the PNG and
pass it: <YouTube {thumbnail} {qr} ... />
EOF
