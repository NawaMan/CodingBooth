#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: codeserver--setup.sh's install_code_server
#
# code-server ships as a ~230MB .deb that coder's install.sh fetches with a bare
# `curl -#fL -C -` -- no timeout, no stall detection, no retry -- so one bad
# connection fails the whole image build. We pre-fetch the package ourselves,
# with bounds, into the cache path their fetch() reuses. This test locks in the
# three things that make that work:
#
#   1. the version is resolved and the cached filename matches what install.sh
#      will look for (get this wrong and the pre-fetch buys nothing -- their
#      fetch() simply downloads it again, unbounded)
#   2. install.sh is pinned to that same version, so it cannot resolve "latest"
#      a second time and land on a newer release than the one just cached
#   3. a failed version probe falls back to the plain installer rather than
#      failing the build -- the old behaviour is the floor, never worse
#
# curl and dpkg are stubbed, so nothing is downloaded and no network is touched.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/codeserver--setup.sh"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/cache"

# The function under test, lifted out of the setup script so the surrounding
# root check and nine install steps do not have to run.
sed -n '/^install_code_server()/,/^}/p' "$SETUP_SCRIPT" > "$STUB/fn.sh"

if [ ! -s "$STUB/fn.sh" ]; then
  print_test_result "false" "$0" "1" "install_code_server should be extractable from codeserver--setup.sh"
  echo "  Looked in: $SETUP_SCRIPT"
  exit 1
fi

# --- Stubs -------------------------------------------------------------------
cat > "$STUB/bin/dpkg" << 'EOF'
#!/bin/bash
[ "${1:-}" = "--print-architecture" ] && echo arm64
EOF

# One curl stub for all four call sites, told apart by their arguments:
#   * the version probe   (releases/latest, -w url_effective)
#   * the size probe      (-I against the .deb)
#   * the installer fetch (code-server.dev/install.sh) -- emits a fake installer
#     that echoes the arguments it was handed, which is how test 2 sees --version
#   * the package download (-o <file>) -- creates the file, downloads nothing
cat > "$STUB/bin/curl" << 'EOF'
#!/bin/bash
args="$*"

# Resolve -o the way real curl does, before dispatching: the destination is a
# property of the invocation, not of which URL it names. The installer fetch is
# downloaded to a file rather than piped into sh (a retried transfer restarts from
# the beginning, so a shell reading the stream would run the partial first attempt
# and then the whole script), and the package download always was -- so both
# branches have to honour it.
out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done

# emit <text> -- writes the response *body*, which goes to the -o file when there
# is one and to stdout otherwise, as curl does.
emit() {
  if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi
}

case "$args" in
  *releases/latest*)
    # The version probe is `-o /dev/null -w '%{url_effective}'`: what it reads is
    # the -w report, not the body, and curl writes that to stdout however -o is
    # set. So this branch deliberately does not use emit.
    printf '%s' "${CB_FAKE_LATEST_URL}"
    ;;
  *code-server.dev/install.sh*)
    # A fake installer that echoes the arguments it was handed, which is how
    # test 2 sees --version.
    emit 'echo "INSTALLER_ARGS=$*"
'
    ;;
  *" -o "*)
    # The package download. Told apart by -o rather than by curl's flag
    # spelling, so tightening the real flags does not silently reroute this
    # stub into the wrong branch.
    [ -n "$out" ] && : > "$out"
    ;;
  *)
    # Everything left is the header-only size probe.
    printf 'HTTP/2 200\r\ncontent-length: 235885798\r\n'
    ;;
esac
exit 0
EOF
chmod +x "$STUB/bin/dpkg" "$STUB/bin/curl"

run_install() {
  PATH="$STUB/bin:/usr/bin:/bin" \
  XDG_CACHE_HOME="$STUB/cache" \
  CB_FAKE_LATEST_URL="$1" \
    bash -c "source '$STUB/fn.sh'; install_code_server" 2>&1
}

ALL_PASSED=true
CACHE_DIR="$STUB/cache/code-server"

# --- Test 1: the resolved version drives the cached filename -----------------
rm -rf "$CACHE_DIR"
OUT="$(run_install 'https://github.com/coder/code-server/releases/tag/v9.9.9')"

if [ -f "$CACHE_DIR/code-server_9.9.9_arm64.deb" ]; then
  print_test_result "true" "$0" "1" "package is cached where install.sh looks for it"
else
  print_test_result "false" "$0" "1" "package should be cached as code-server_9.9.9_arm64.deb"
  echo "  Cache contents: $(ls -A "$CACHE_DIR" 2>/dev/null || echo '(none)')"
  ALL_PASSED=false
fi

# --- Test 2: install.sh is pinned to that version ----------------------------
if echo "$OUT" | grep -qF 'INSTALLER_ARGS=--version 9.9.9'; then
  print_test_result "true" "$0" "2" "install.sh is pinned to the version just cached"
else
  print_test_result "false" "$0" "2" "install.sh should be invoked with --version 9.9.9"
  echo "  Output: $OUT"
  ALL_PASSED=false
fi

# --- Test 3: the size is named before the wait -------------------------------
# A 224MB download that prints nothing for minutes is indistinguishable from a
# hang, and the natural response (^C) discards the RUN layer.
if echo "$OUT" | grep -qE 'Downloading code-server 9\.9\.9 for arm64 \(224 MB\)'; then
  print_test_result "true" "$0" "3" "download names the size up front"
else
  print_test_result "false" "$0" "3" "download should name version, arch and size"
  echo "  Output: $OUT"
  ALL_PASSED=false
fi

# --- Test 4: an unresolvable version falls back to the plain installer -------
rm -rf "$CACHE_DIR"
OUT_FALLBACK="$(run_install 'https://github.com/coder/code-server/releases')"

if echo "$OUT_FALLBACK" | grep -qF 'INSTALLER_ARGS=' \
   && ! echo "$OUT_FALLBACK" | grep -qF -- '--version'; then
  print_test_result "true" "$0" "4" "unresolvable version falls back to the plain installer"
else
  print_test_result "false" "$0" "4" "fallback should run install.sh with no --version"
  echo "  Output: $OUT_FALLBACK"
  ALL_PASSED=false
fi

# --- Test 5: the fallback says why ------------------------------------------
if echo "$OUT_FALLBACK" | grep -qF 'Could not resolve the latest code-server version'; then
  print_test_result "true" "$0" "5" "fallback explains itself in the build log"
else
  print_test_result "false" "$0" "5" "fallback should say why it is using install.sh as-is"
  echo "  Output: $OUT_FALLBACK"
  ALL_PASSED=false
fi

[ "$ALL_PASSED" = true ]
