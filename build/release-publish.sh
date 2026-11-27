#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# release-publish.sh — create or update a GitHub release and upload its files, retrying what fails.
#
#   build/release-publish.sh --tag <tag> --title <title> --notes-file <file>
#                            [--latest | --not-latest] [--target <commit>] <file>...
#
# Replaces softprops/action-gh-release in release-binary-and-wrapper.yaml. That action uploads every
# file at once, and with ~120 files the burst trips GitHub's secondary rate limit (0.82.0, and both
# attempts of 0.83.0), with no retry. So this:
#
#   - creates the release when it is missing, else updates its title, notes and latest flag;
#   - uploads one file at a time (`gh release upload --clobber`), retrying each failure with a
#     growing wait (CB_RELEASE_RETRY_WAIT seconds, default 60, doubling, capped at 600) up to
#     CB_RELEASE_RETRIES attempts (default 6). GitHub asks for at least a minute after a
#     secondary rate limit. Any failure is retried: upload failures are almost always transient;
#   - skips a file the release already has with the same sha256, so a re-run uploads only what
#     an earlier attempt did not finish (and does not burst again);
#   - keeps going past a file that never uploads, then exits 1 naming every such file.
#
# The repository is GH_REPO, else GITHUB_REPOSITORY (set on a GitHub Actions runner).
# Needs gh (authenticated, GH_TOKEN/GITHUB_TOKEN) and sha256sum.

set -euo pipefail

usage() { sed -n '7,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

TAG="" TITLE="" NOTES="" TARGET="" LATEST=""
FILES=()
while (( $# > 0 )); do
  case "$1" in
    --tag)        TAG="${2:?}"; shift 2 ;;
    --title)      TITLE="${2:?}"; shift 2 ;;
    --notes-file) NOTES="${2:?}"; shift 2 ;;
    --target)     TARGET="${2:?}"; shift 2 ;;
    --latest)     LATEST=true; shift ;;
    --not-latest) LATEST=false; shift ;;
    --)           shift; FILES+=("$@"); break ;;
    -*)           echo "release-publish: unknown option $1" >&2; usage ;;
    *)            FILES+=("$1"); shift ;;
  esac
done
[[ -n "$TAG" && -n "$TITLE" && -n "$NOTES" ]] || usage
[[ -f "$NOTES" ]] || { echo "release-publish: notes file not found: $NOTES" >&2; exit 2; }
(( ${#FILES[@]} > 0 )) || { echo "release-publish: no files to upload" >&2; exit 2; }
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "release-publish: not a file: $f" >&2; exit 2; }
done

export GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
[[ -n "$GH_REPO" ]] || { echo "release-publish: set GH_REPO (owner/repo)" >&2; exit 2; }

RETRIES="${CB_RELEASE_RETRIES:-6}"
WAIT="${CB_RELEASE_RETRY_WAIT:-60}"
WAIT_CAP=600

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

# retry <what> <cmd>... — run cmd, retrying on failure; its stdout passes through.
retry() {
  local what="$1"; shift
  local attempt=1 wait="$WAIT"
  while :; do
    if "$@" 2>"$ERR"; then return 0; fi
    local why="failed"
    grep -qi 'rate limit' "$ERR" && why="rate limited"
    if (( attempt >= RETRIES )); then
      echo "❌ $what: $why after $attempt attempts: $(head -c 300 "$ERR")" >&2
      return 1
    fi
    echo "⏳ $what: $why (attempt $attempt/$RETRIES), retrying in ${wait}s: $(head -c 200 "$ERR")" >&2
    sleep "$wait"
    attempt=$((attempt + 1))
    wait=$((wait * 2)); (( wait > WAIT_CAP )) && wait=$WAIT_CAP
  done
}

# release_exists — 0 when the release exists, 1 when it does not, retried on anything else.
release_exists() {
  local attempt=1 wait="$WAIT"
  while :; do
    if gh release view "$TAG" --json tagName >/dev/null 2>"$ERR"; then return 0; fi
    grep -qi 'not found' "$ERR" && return 1
    if (( attempt >= RETRIES )); then
      echo "❌ looking up release $TAG: $(head -c 300 "$ERR")" >&2
      exit 1
    fi
    echo "⏳ looking up release $TAG failed (attempt $attempt/$RETRIES), retrying in ${wait}s" >&2
    sleep "$wait"
    attempt=$((attempt + 1))
    wait=$((wait * 2)); (( wait > WAIT_CAP )) && wait=$WAIT_CAP
  done
}

latest_flag=()
[[ -n "$LATEST" ]] && latest_flag=("--latest=$LATEST")

if release_exists; then
  echo "📝 Updating release $TAG"
  retry "updating release $TAG" \
    gh release edit "$TAG" --title "$TITLE" --notes-file "$NOTES" --draft=false --prerelease=false \
      "${latest_flag[@]}" >/dev/null
else
  echo "🆕 Creating release $TAG"
  target_flag=()
  [[ -n "$TARGET" ]] && target_flag=(--target "$TARGET")
  retry "creating release $TAG" \
    gh release create "$TAG" --title "$TITLE" --notes-file "$NOTES" "${target_flag[@]}" \
      "${latest_flag[@]}" >/dev/null
fi

# What the release already holds: name<TAB>sha256, for fully uploaded assets with a digest.
declare -A HAVE=()
listing="$(retry "listing assets of $TAG" \
  gh release view "$TAG" --json assets \
    --jq '.assets[] | select(.state == "uploaded") | "\(.name)\t\(.digest // "")"')"
while IFS=$'\t' read -r name digest; do
  [[ -n "$name" ]] && HAVE["$name"]="${digest#sha256:}"
done <<<"$listing"

uploaded=0 skipped=0 failed=()
for f in "${FILES[@]}"; do
  name="$(basename "$f")"
  sum="$(sha256sum "$f" | cut -d' ' -f1)"
  if [[ -n "${HAVE[$name]:-}" && "${HAVE[$name]}" == "$sum" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  if retry "uploading $name" gh release upload "$TAG" "$f" --clobber >/dev/null; then
    echo "✅ Uploaded $name"
    uploaded=$((uploaded + 1))
  else
    failed+=("$name")
  fi
done

echo "Release $TAG: $uploaded uploaded, $skipped already there, ${#failed[@]} failed"
if (( ${#failed[@]} > 0 )); then
  echo "::error::release $TAG is missing: ${failed[*]} — re-run the job; files already uploaded are skipped" >&2
  exit 1
fi
