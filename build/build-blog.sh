#!/usr/bin/env bash
#
# Build the CodingBooth blog (the GeekPresent site under geekpresent/) and stage
# it into site/blog/ so it ships with the marketing site to codingbooth.io/blog/.
#
# Run from anywhere — it resolves the repo root from its own location:
#   build/build-blog.sh
#
# Override the public base URL if needed (default: https://codingbooth.io/blog):
#   GEEKPRESENT_SITE_URL=https://staging.example/blog build/build-blog.sh
#
set -euo pipefail

# Repo root = the parent of this script's dir (build/), resolved absolutely so the
# destructive rm/cp below always target the right paths regardless of the cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Public base URL for the absolute-only SEO tags (canonical / og:url / sitemap).
# Without this the build falls back to the GeekPresent GitHub Pages URL.
BLOG_URL="${GEEKPRESENT_SITE_URL:-https://codingbooth.io/blog}"

echo ">> Building blog (base URL: $BLOG_URL) ..."

# Build the static blog inside the booth (reproducible toolchain). The env var is
# set inside the container command so build-static.sh inherits it there.
cd "$ROOT_DIR/geekpresent"
./booth -- "rm -rf dist && GEEKPRESENT_SITE_URL=$BLOG_URL ./build-static.sh dist"

# Guard: only replace the staged copy if the build actually produced output, so a
# failed build can never wipe site/blog and leave nothing (set -e covers the build
# itself; this catches a silent/empty result).
if [ ! -f "$ROOT_DIR/geekpresent/dist/index.html" ]; then
	echo "ERROR: build produced no geekpresent/dist/index.html — aborting; site/blog left untouched." >&2
	exit 1
fi

# Stage into the site docroot for the normal site upload.
echo ">> Staging into site/blog/ ..."
rm -rf "$ROOT_DIR/site/blog"
cp -R  "$ROOT_DIR/geekpresent/dist" "$ROOT_DIR/site/blog"

echo "✓ Blog staged at site/blog/  ->  upload it with the site so it serves at $BLOG_URL"
