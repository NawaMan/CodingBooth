#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb-github-api.sh — a setup's "latest" lookup survives a rate-limited
# api.github.com
#
# Unauthenticated api.github.com allows 60 requests an hour per IP; on a shared CI
# runner a dozen setups came back with an empty "latest" and failed the 0.83.0
# release run. The helper is the drop-in for `curl https://api.github.com/<path>`:
#
#   1. The API answers: its JSON is printed as is.
#   2. With GH_TOKEN set, the call is authenticated, and the token is not on
#      curl's command line.
#   3. The API fails on releases/latest: the github.com redirect stands in, as
#      {"tag_name": "<tag>"}, which a setup's own grep still matches.
#   4. The API fails on a release list: the releases.atom feed stands in, newest
#      first, with percent-encoded tags decoded (kustomize%2Fv5.8.3).
#   5. Nothing answers: it fails, with nothing on stdout.
#   6. The catalog's setups call it, and no setup asks api.github.com for
#      releases/latest by itself.
#
# Hermetic: curl is a stub that answers per URL and logs its arguments.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
HELPER="$SETUPS/cb-github-api.sh"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin"
export STUB_LOG="$STUB/calls.log"

# curl: API_MODE=ok answers the API; anything else fails it (22, as -f does on a 403).
# github.com's redirect and feed always answer. The headers curl was given, including
# one read from a file (-H @file), are logged too.
cat > "$STUB/bin/curl" <<'EOF'
#!/bin/bash
echo "ARGV curl $*" >> "$STUB_LOG"
url="" prev=""
for a in "$@"; do
  [[ "$prev" == -H && "$a" == @* ]] && echo "HEADER $(cat "${a#@}")" >> "$STUB_LOG"
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
case "$url" in
  https://api.github.com/*)
    [[ "${API_MODE:-ok}" == ok ]] || { echo "curl: (22) The requested URL returned error: 403" >&2; exit 22; }
    echo '{"tag_name": "v9.9.9", "assets": []}' ;;
  https://github.com/*/releases/latest)
    printf '%s' "https://github.com/${url#https://github.com/}" | sed 's|/latest$|/tag/v1.2.3|' ;;
  https://github.com/*/releases.atom)
    r="${url#https://github.com/}"; r="${r%/releases.atom}"
    cat <<FEED
<feed><entry><link rel="alternate" type="text/html" href="https://github.com/$r/releases/tag/kyaml%2Fv0.21.3"/></entry>
<entry><link rel="alternate" type="text/html" href="https://github.com/$r/releases/tag/kustomize%2Fv5.8.3"/></entry></feed>
FEED
    ;;
  *) exit 6 ;;
esac
EOF
chmod +x "$STUB/bin/curl"
run() { PATH="$STUB/bin:$PATH" "$HELPER" "$@"; }

ALL_PASSED=true
check() {  # check <num> <ok> <desc> [detail]
  if [[ "$2" == true ]]; then
    print_test_result "true" "$0" "$1" "$3"
  else
    print_test_result "false" "$0" "$1" "$3"; [[ -n "${4:-}" ]] && echo "      $4"
    ALL_PASSED=false
  fi
}

# 1. The API answers.
: > "$STUB_LOG"
OUT="$(API_MODE=ok GH_TOKEN= GITHUB_TOKEN= run repos/junegunn/fzf/releases/latest)"
[[ "$OUT" == '{"tag_name": "v9.9.9", "assets": []}' ]] && ok=true || ok=false
check 1 "$ok" "the API's JSON is printed as is" "got: $OUT"

# 2. Authenticated, and the token is not in argv.
: > "$STUB_LOG"
API_MODE=ok GH_TOKEN=sekrit-token run repos/junegunn/fzf/releases/latest >/dev/null
if grep -qxF 'HEADER Authorization: Bearer sekrit-token' "$STUB_LOG" && ! grep '^ARGV' "$STUB_LOG" | grep -qF sekrit-token; then
  ok=true; else ok=false; fi
check 2 "$ok" "GH_TOKEN authenticates the call, and is not on curl's command line" "log: $(tr '\n' '|' < "$STUB_LOG")"

# 3. releases/latest through the redirect; fzf's own pattern still finds it.
: > "$STUB_LOG"
OUT="$(API_MODE=fail run repos/junegunn/fzf/releases/latest)"
TAG="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' <<<"$OUT" | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')"
[[ "$OUT" == '{"tag_name": "v1.2.3"}' && "$TAG" == 1.2.3 ]] && ok=true || ok=false
check 3 "$ok" "a failed API falls back to the releases/latest redirect, as {\"tag_name\": …}" "got: $OUT"

# 4. A release list through the feed, tags decoded, kustomize's pattern still finds its own.
OUT="$(API_MODE=fail run 'repos/kubernetes-sigs/kustomize/releases?per_page=30')"
KTAG="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"kustomize/v[^"]+"' <<<"$OUT" | head -1 | sed -E 's/.*"kustomize\/v([^"]+)".*/\1/')"
[[ "$OUT" == '[{"tag_name": "kyaml/v0.21.3"}, {"tag_name": "kustomize/v5.8.3"}]' && "$KTAG" == 5.8.3 ]] && ok=true || ok=false
check 4 "$ok" "a failed API on a release list falls back to releases.atom, tags decoded" "got: $OUT"

# 5. Nothing answers (another API path has no stand-in).
if OUT="$(API_MODE=fail run repos/x/y/releases/tags/v1 2>/dev/null)"; then ok=false; else [[ -z "$OUT" ]] && ok=true || ok=false; fi
check 5 "$ok" "with nothing to answer it fails, printing nothing on stdout" "got: $OUT"

# 6. The catalog uses it.
USERS="$(grep -l 'cb-github-api.sh' "$SETUPS"/*--setup.sh | wc -l)"
DIRECT="$(grep -lE 'curl[^#]*https://api\.github\.com/repos/[^ "]+/releases/latest' "$SETUPS"/*--setup.sh || true)"
[[ "$USERS" -ge 50 && -z "$DIRECT" ]] && ok=true || ok=false
check 6 "$ok" "$USERS setups use it, and none asks api.github.com for releases/latest itself" "direct: $DIRECT"

[[ "$ALL_PASSED" == true ]]
