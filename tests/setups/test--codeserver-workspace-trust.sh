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
# root check, code-server install and dropins wiring do not have to run.
sed -n '/^# Settings$/,/^JSON$/p' "$SETUP_SCRIPT" > "$STUB/fn.sh"

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
if python3 -m json.tool "$SETTINGS_JSON" > /dev/null 2>&1; then
  print_test_result "true" "$0" "2" "settings.json is valid JSON"
else
  print_test_result "false" "$0" "2" "settings.json should be valid JSON"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

# --- Test 3: workspace trust is disabled --------------------------------------
if python3 -c "
import json, sys
with open('$SETTINGS_JSON') as f:
    data = json.load(f)
sys.exit(0 if data.get('security.workspace.trust.enabled') is False else 1)
"; then
  print_test_result "true" "$0" "3" "security.workspace.trust.enabled is false"
else
  print_test_result "false" "$0" "3" "security.workspace.trust.enabled should be false"
  echo "  Contents: $(cat "$SETTINGS_JSON" 2>/dev/null)"
  ALL_PASSED=false
fi

[ "$ALL_PASSED" = true ]
