#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: codeserver--setup.sh's generated settings.json disables workspace
# trust
#
# code-server always shows the "Do you trust the authors of the files in this
# folder?" dialog on open, unlike desktop VS Code (already launched with
# --disable-workspace-trust in vscode--setup.sh). The settings.json seeded for
# every code-server user carries "security.workspace.trust.enabled": false so
# the same prompt never appears there either. This locks in that the key
# lands, with the right value, in valid JSON -- a bare grep for the line would
# not catch a dropped comma turning the file unparsable.
#
# The defaults go only into a missing or empty file. An existing one is the
# user's, and under +settings-shared / +settings-cache it is a .booth mount, so
# a rewrite on every launch would replace the team's committed file on the host.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/codeserver--setup.sh"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT

# The settings.json generation block, lifted out of the setup script so the
# root check, code-server install and dropins wiring do not have to run. It ends
# at the "fi" right after the heredoc that writes the file.
awk '/^# Settings$/ {p=1} p {print} p && /^JSON$/ {getline; print; exit}' \
  "$SETUP_SCRIPT" > "$STUB/fn.sh"

if [ ! -s "$STUB/fn.sh" ]; then
  print_test_result "false" "$0" "1" "the settings.json generation block should be extractable"
  echo "  Looked in: $SETUP_SCRIPT"
  exit 1
fi

CSHOME="$STUB/home"
mkdir -p "$CSHOME"
bash -c "CSHOME='$CSHOME'; source '$STUB/fn.sh'"

SETTINGS_JSON="$CSHOME/.local/share/code-server/User/settings.json"
ALL_PASSED=true

# --- Test 1: the file is written where code-server reads it ------------------
if [ -f "$SETTINGS_JSON" ]; then
  print_test_result "true" "$0" "1" "settings.json is written under the user's code-server config"
else
  print_test_result "false" "$0" "1" "settings.json should exist at $SETTINGS_JSON"
  ALL_PASSED=false
fi

# --- Test 2: it is valid JSON -------------------------------------------------
# Parsing is the whole point of this case (a dropped comma is what a grep would
# miss), so it needs a parser on the host: python3 when it is real — see
# have_python3 in common--source.sh for why being on PATH is not enough — else
# jq. With neither, say so rather than report a pass or a failure of the file.
JSON_PARSE=""
if have_python3; then
  JSON_PARSE="python3 -m json.tool"
elif command -v jq >/dev/null 2>&1; then
  JSON_PARSE="jq -e ."
fi
if [[ -z "$JSON_PARSE" ]]; then
  echo "SKIP: no JSON parser on this host (python3 or jq); settings.json parsability not checked"
elif $JSON_PARSE "$SETTINGS_JSON" > /dev/null 2>&1; then
  print_test_result "true" "$0" "2" "settings.json is valid JSON"
else
  print_test_result "false" "$0" "2" "settings.json should be valid JSON"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

# --- Test 3: workspace trust is disabled --------------------------------------
# The key and its value, read back from the parsed file where there is a parser
# and matched as written otherwise — the same line Test 5 looks for. Test 2 is
# the one that answers whether the file as a whole parses.
trust_is_disabled() {
  if have_python3; then
    python3 -c "
import json, sys
with open('$SETTINGS_JSON') as f:
    data = json.load(f)
sys.exit(0 if data.get('security.workspace.trust.enabled') is False else 1)
"
  elif command -v jq >/dev/null 2>&1; then
    [[ "$(jq -r '."security.workspace.trust.enabled"' "$SETTINGS_JSON" 2>/dev/null)" == "false" ]]
  else
    grep -q '"security.workspace.trust.enabled": false' "$SETTINGS_JSON"
  fi
}
if trust_is_disabled; then
  print_test_result "true" "$0" "3" "security.workspace.trust.enabled is false"
else
  print_test_result "false" "$0" "3" "security.workspace.trust.enabled should be false"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

# --- Test 4: an existing settings.json is left as it is ----------------------
echo '{"team.setting": 42}' > "$SETTINGS_JSON"
bash -c "CSHOME='$CSHOME'; source '$STUB/fn.sh'"
if [ "$(cat "$SETTINGS_JSON")" = '{"team.setting": 42}' ]; then
  print_test_result "true" "$0" "4" "an existing settings.json is not overwritten"
else
  print_test_result "false" "$0" "4" "an existing settings.json should not be overwritten"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

# --- Test 5: an empty settings.json gets the defaults -------------------------
# booth creates a missing shared-files / cache-files entry as an empty file.
: > "$SETTINGS_JSON"
bash -c "CSHOME='$CSHOME'; source '$STUB/fn.sh'"
if grep -q '"security.workspace.trust.enabled": false' "$SETTINGS_JSON"; then
  print_test_result "true" "$0" "5" "an empty settings.json is filled with the defaults"
else
  print_test_result "false" "$0" "5" "an empty settings.json should be filled with the defaults"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

[ "$ALL_PASSED" = true ]
