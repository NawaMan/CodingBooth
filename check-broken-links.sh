#!/usr/bin/env bash
# Run the lychee link checker against repo docs (**/*.md) and site HTML (site/**/*.html).
# Mirrors the args used by .github/workflows/link-check.yaml so local runs match CI.
#
# Usage:
#   ./check-broken-links.sh                    # default: all markdown + site HTML
#   ./check-broken-links.sh --verbose          # extra detail
#   ./check-broken-links.sh README.md          # override paths (full control)
#   ./check-broken-links.sh --dump <paths>     # any lychee flag works
#
# Exclude patterns (localhost, LinkedIn) live in .lycheeignore — edit that file
# to skip more domains; no changes to this script are needed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

if ! command -v lychee >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: lychee not found in PATH.

Install with one of:
  cargo install lychee     # any platform with Rust
  brew  install lychee     # macOS / Linuxbrew
  apt   install lychee     # Debian/Ubuntu (newer releases)

Or see: https://lychee.cli.rs/installation/
EOF
  exit 127
fi

LYCHEE_ARGS=(
  --cache
  --max-cache-age 1d
  --no-progress
  --accept '200..=299,403,429'
)

# Split caller args into flags vs positional paths. If the caller passed any
# positional path, use those instead of the defaults; flags are always layered in.
EXTRA_FLAGS=()
USER_INPUTS=()
for arg in "$@"; do
  case "$arg" in
    -*) EXTRA_FLAGS+=("$arg") ;;
    *)  USER_INPUTS+=("$arg") ;;
  esac
done

if [ ${#USER_INPUTS[@]} -gt 0 ]; then
  exec lychee "${LYCHEE_ARGS[@]}" "${EXTRA_FLAGS[@]}" "${USER_INPUTS[@]}"
fi

# Default inputs: only files tracked by git. That skips vendored / generated
# dirs (node_modules, .angular, dist, obj, .booth/cache, etc.) without needing
# a hand-maintained exclude list, since git already knows what's ignored.
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git work tree and no input paths given." >&2
  echo "Pass paths explicitly, e.g.: $0 README.md docs/" >&2
  exit 2
fi

DEFAULT_INPUTS=()
while IFS= read -r path; do
  DEFAULT_INPUTS+=("$path")
done < <(git ls-files -z | tr '\0' '\n' | grep -E '(\.md$|^site/.*\.html$)' || true)

if [ ${#DEFAULT_INPUTS[@]} -eq 0 ]; then
  echo "ERROR: no tracked .md or site/**/*.html files found to scan." >&2
  exit 2
fi

exec lychee "${LYCHEE_ARGS[@]}" "${EXTRA_FLAGS[@]}" "${DEFAULT_INPUTS[@]}"
