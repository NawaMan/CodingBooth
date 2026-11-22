#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: freeplane--setup.sh asks GitHub for the .deb under the name GitHub
# serves it by
#
# The package is named freeplane_<version>~upstream-1_all.deb, but a release
# asset cannot have "~" in its name: GitHub stores it as
# freeplane_<version>.upstream-1_all.deb. The setup asked for the "~" spelling,
# which is a 404 for every version, so `setup freeplane` could not install
# anything at all.
#
#   1. With no argument, the setup downloads the catalog's default version, as
#      release-<version>/freeplane_<version>.upstream-1_all.deb.
#   2. A version given as the argument is the one downloaded, in the same form.
#   3. No download URL has a "~" in it.
#   4. The file curl wrote is the file apt-get installs.
#   5. A failed download fails the setup, and nothing is installed.
#
# Hermetic: curl, apt-get, java and rm are stubs that log their arguments.
# Nothing is downloaded, installed, or removed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/freeplane--setup.sh"
TEMPLATE="$REPO_ROOT/templates/tools/freeplane/template.toml"

# The default version is catalog data: read it, do not spell it here.
DEFAULT_VER="$(awk '/^\[params\.FREEPLANE_VERSION\]/{f=1;next} f && /^default/{gsub(/[" ]/,"",$0); sub(/^default=/,"",$0); print; exit}' "$TEMPLATE")"
if [[ -z "$DEFAULT_VER" ]]; then
  print_test_result "false" "$0" "0" "Could not read FREEPLANE_VERSION's default from $TEMPLATE"
  exit 1
fi

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin"
LOG="$STUB/calls.log"

# curl: CURL_MODE=fail fails the download the way a 404 does under -f.
cat > "$STUB/bin/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$STUB_LOG"
[[ "${CURL_MODE:-ok}" == fail ]] && { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
exit 0
EOF
cat > "$STUB/bin/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >> "$STUB_LOG"
exit 0
EOF
# java is "already installed", so the setup does not go looking for a JRE.
cat > "$STUB/bin/java" <<'EOF'
#!/bin/bash
echo 'openjdk version "25" (stub)' >&2
EOF
# rm: the setup clears /var/lib/apt/lists and its .deb; log it, remove nothing.
cat > "$STUB/bin/rm" <<'EOF'
#!/bin/bash
echo "rm $*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$STUB/bin"/*

run_setup() {   # run_setup <curl-mode> [args...] ; sets OUTPUT and RC
  local mode="$1"; shift
  : > "$LOG"
  RC=0
  OUTPUT=$(env EUID=0 PATH="$STUB/bin:$PATH" STUB_LOG="$LOG" CURL_MODE="$mode" \
    bash "$SCRIPT" "$@" 2>&1) || RC=$?
}

url_for() { echo "https://github.com/freeplane/freeplane/releases/download/release-$1/freeplane_$1.upstream-1_all.deb"; }

# --- Test 1: no argument → the catalog default, in the form GitHub serves ------
run_setup ok
if [[ $RC -eq 0 ]] && grep -qF -- "$(url_for "$DEFAULT_VER")" "$LOG"; then
  print_test_result "true"  "$0" "1" "No argument: downloads the catalog default ($DEFAULT_VER) as freeplane_<version>.upstream-1_all.deb"
else
  print_test_result "false" "$0" "1" "Expected $(url_for "$DEFAULT_VER"); rc=$RC; log: $(cat "$LOG"); output: $OUTPUT"
  exit 1
fi
DEFAULT_LOG="$(cat "$LOG")"

# --- Test 2: a version argument is the one downloaded --------------------------
OTHER_VER="0.0.1"
run_setup ok "$OTHER_VER"
if [[ $RC -eq 0 ]] && grep -qF -- "$(url_for "$OTHER_VER")" "$LOG" && ! grep -qF -- "release-$DEFAULT_VER/" "$LOG"; then
  print_test_result "true"  "$0" "2" "A version argument is the version downloaded"
else
  print_test_result "false" "$0" "2" "Expected $(url_for "$OTHER_VER") and nothing for $DEFAULT_VER; rc=$RC; log: $(cat "$LOG")"
  exit 1
fi

# --- Test 3: no download URL carries a "~" -------------------------------------
if printf '%s\n%s\n' "$DEFAULT_LOG" "$(cat "$LOG")" | grep '^curl ' | grep -q '~'; then
  print_test_result "false" "$0" "3" "A download URL has a '~' in it, which GitHub answers with 404: $(grep '^curl ' "$LOG")"
  exit 1
else
  print_test_result "true"  "$0" "3" "No download URL has a '~' in it"
fi

# --- Test 4: the file curl wrote is the file apt-get installs -------------------
DEB="$(grep '^curl ' "$LOG" | sed -E 's/.* -o ([^ ]+) .*/\1/')"
if [[ -n "$DEB" ]] && grep -qE "^apt-get install .* ${DEB}\$" "$LOG"; then
  print_test_result "true"  "$0" "4" "apt-get installs the file the download wrote ($DEB)"
else
  print_test_result "false" "$0" "4" "Expected apt-get install of '$DEB'; log: $(cat "$LOG")"
  exit 1
fi

# --- Test 5: a failed download fails the setup; nothing is installed -----------
run_setup fail
if [[ $RC -ne 0 ]] && ! grep -qE '^apt-get install .*\.deb$' "$LOG"; then
  print_test_result "true"  "$0" "5" "A failed download fails the setup, and no .deb is installed"
else
  print_test_result "false" "$0" "5" "Expected a non-zero exit and no .deb install; rc=$RC; log: $(cat "$LOG")"
  exit 1
fi
