#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# cb-github-api.sh <api-path>
#
# Prints the GitHub REST API's JSON for <api-path> (e.g. repos/junegunn/fzf/releases/latest),
# the drop-in for `curl -fsSL https://api.github.com/<api-path>` in a setup's "latest" lookup.
#
# Unauthenticated api.github.com allows 60 requests an hour per IP. A CI runner's IP is shared,
# and the 0.83.0 release run lost a dozen complex tests to it, each "latest" coming back empty.
# So:
#   - with GH_TOKEN (or GITHUB_TOKEN) set, the call is authenticated (5000/hour);
#   - when the API fails, two lookups that are not API calls stand in for it:
#       repos/<owner>/<repo>/releases/latest  → the github.com/<repo>/releases/latest redirect,
#                                                printed as {"tag_name": "<tag>"}
#       repos/<owner>/<repo>/releases[?…]     → the github.com/<repo>/releases.atom feed (newest
#                                                first, the API's order), printed as
#                                                [{"tag_name": "<tag>"}, …]
#     Only tag_name is there: a caller that needs more (assets, digests) gets it from the API
#     alone, as before.
# Exits non-zero, printing nothing on stdout, when nothing answers.

set -euo pipefail

path="${1:?usage: cb-github-api.sh <api-path>}"
path="${path#/}"
path="${path#https://api.github.com/}"

curl_args=(-fsSL -H 'Accept: application/vnd.github+json')
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$token" ]]; then
  # From a file descriptor, so the token is not on curl's command line (ps would show it).
  exec {token_fd}< <(printf 'Authorization: Bearer %s\n' "$token")
  curl_args+=(-H "@/dev/fd/${token_fd}")
fi

if out="$(curl --retry 3 --retry-delay 2 "${curl_args[@]}" "https://api.github.com/${path}" 2>/dev/null)" && [[ -n "$out" ]]; then
  printf '%s\n' "$out"
  exit 0
fi

# A tag in a github.com URL is percent-encoded (kustomize's "kustomize/v5.8.0" is kustomize%2Fv5.8.0).
url_decode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }
json_tag() { local t="$1"; t="${t//\\/\\\\}"; printf '{"tag_name": "%s"}' "${t//\"/\\\"}"; }

if [[ "$path" =~ ^repos/([^/]+/[^/]+)/releases/latest$ ]]; then
  repo="${BASH_REMATCH[1]}"
  location="$(curl --retry 3 --retry-delay 2 -fsS -o /dev/null -w '%{redirect_url}' \
                "https://github.com/${repo}/releases/latest" 2>/dev/null || true)"
  if [[ "$location" == */releases/tag/* ]]; then
    tag="$(url_decode "${location##*/releases/tag/}")"
    if [[ -n "$tag" ]]; then
      json_tag "$tag"; echo
      exit 0
    fi
  fi
elif [[ "$path" =~ ^repos/([^/]+/[^/]+)/releases(\?.*)?$ ]]; then
  repo="${BASH_REMATCH[1]}"
  feed="$(curl --retry 3 --retry-delay 2 -fsSL "https://github.com/${repo}/releases.atom" 2>/dev/null || true)"
  tags=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && tags+=("$(url_decode "$t")")
  done < <(grep -oE "href=\"https://github.com/${repo}/releases/tag/[^\"]+\"" <<<"$feed" \
             | sed -E 's|.*/releases/tag/([^"]+)"|\1|' || true)
  if (( ${#tags[@]} > 0 )); then
    printf '['
    for i in "${!tags[@]}"; do
      (( i > 0 )) && printf ', '
      json_tag "${tags[$i]}"
    done
    printf ']\n'
    exit 0
  fi
fi

echo "cb-github-api: no answer for https://api.github.com/${path} (rate limited? set GH_TOKEN)" >&2
exit 1
