#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Conservative shared extensions: editors/desktop/shell — shared only, no cache.

source "$(dirname "$0")/test-helpers--source.sh"

begin

assert_file() {
  local path="$1"
  local label="$2"
  TEST_COUNT=$((TEST_COUNT + 1))
  local pad
  pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
  echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
  if [ -f "$path" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $path to exist"
  fi
}

run rm -Rf "$prj" ; mkdir -p "$prj"
run booth config "$prj" --no-tui --select \
  "codeserver+settings-shared+keybindings-shared+snippets-shared/neovim+config-shared/notebook+lab-settings-shared/xfce+keyboard-shortcuts-shared/zsh+starship-shared/dbeaver+connections-shared+drivers-shared+scripts-shared"

assert_file "$prj/.booth/shared/home/coder/.local/share/code-server/User/settings.json" \
  "codeserver settings.json"
assert_file "$prj/.booth/shared/home/coder/.local/share/code-server/User/keybindings.json" \
  "codeserver keybindings.json"
assert_file "$prj/.booth/shared/home/coder/.local/share/code-server/User/snippets/.mount-this" \
  "codeserver snippets dir"
assert_file "$prj/.booth/shared/home/coder/.config/nvim/.mount-this" \
  "neovim config dir"
assert_file "$prj/.booth/shared/home/coder/.jupyter/lab/user-settings/.mount-this" \
  "jupyter lab user-settings"
assert_file "$prj/.booth/shared/home/coder/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" \
  "xfce keyboard shortcuts"
assert_file "$prj/.booth/shared/home/coder/.config/starship.toml" \
  "starship.toml"
assert_file "$prj/.booth/shared/home/coder/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json" \
  "dbeaver data-sources"
assert_file "$prj/.booth/shared/home/coder/.local/share/DBeaverData/drivers/.mount-this" \
  "dbeaver drivers dir"
assert_file "$prj/.booth/shared/home/coder/.local/share/DBeaverData/workspace6/.metadata/.config/.mount-this" \
  "dbeaver drivers.xml config dir"
assert_file "$prj/.booth/shared/home/coder/.local/share/DBeaverData/workspace6/General/Scripts/.mount-this" \
  "dbeaver Scripts dir"

TEST_COUNT=$((TEST_COUNT + 1))
if [ -d "$prj/.booth/cache" ]; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: no cache dir for conservative shared")
  echo -e "Test ${TEST_COUNT}: no cache dir for conservative shared ............. \033[31mFAILED\033[0m"
else
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: no cache dir for conservative shared ............. \033[32mPASSED\033[0m"
fi

TEST_COUNT=$((TEST_COUNT + 1))
if grep -qE 'cache-dirs|cache-files' "$prj/.booth/config.toml"; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: config has no cache-* keys")
  echo -e "Test ${TEST_COUNT}: config has no cache-* keys ....................... \033[31mFAILED\033[0m"
else
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: config has no cache-* keys ....................... \033[32mPASSED\033[0m"
fi

finally
