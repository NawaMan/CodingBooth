#!/bin/bash
# code-ext-pkg: arbitrary VS Code / code-server extensions by marketplace id,
# alongside the curated per-language `+vscode-ext` extensions.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- single extension id ---
run booth config $prj --no-tui --variant codeserver --select "code-ext-pkg:elixir-lsp.elixir-ls"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg CODE_EXT_PKGS=" 'elixir-lsp.elixir-ls'         "CODE_EXT_PKGS arg for single id"
assert-line "$boothfile" "install code-extension " '${CODE_EXT_PKGS}'       "install code-extension line"

# --- multiple ids (order may be normalized by the config writer) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant codeserver --select "code-ext-pkg:elixir-lsp.elixir-ls,ms-python.python"
boothfile="$prj/.booth/Boothfile"
FOUND_EXTS="$(grep '^arg CODE_EXT_PKGS=' "$boothfile" | head -1 | sed 's/^arg CODE_EXT_PKGS=//')"
TEST_COUNT=$((TEST_COUNT + 1))
if echo ",${FOUND_EXTS}," | grep -q ',elixir-lsp.elixir-ls,' && echo ",${FOUND_EXTS}," | grep -q ',ms-python.python,'; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: CODE_EXT_PKGS arg for multiple ids ................ "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: CODE_EXT_PKGS arg for multiple ids")
  echo -n "Test ${TEST_COUNT}: CODE_EXT_PKGS arg for multiple ids ................ "
  echo -e "\033[31mFAILED\033[0m"
  echo "  FOUND: arg CODE_EXT_PKGS=${FOUND_EXTS}"
fi

# --- version pin via id@version ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant codeserver --select "code-ext-pkg:eamodio.gitlens@15.6.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg CODE_EXT_PKGS=" 'eamodio.gitlens@15.6.0'      "CODE_EXT_PKGS version pin"

# --- alongside a curated per-language extension: both land, in the right order ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant codeserver --select "elixir+vscode-ext/code-ext-pkg:eamodio.gitlens"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup elixir-code-extension" ''                   "curated elixir extension still selected"
assert-line "$boothfile" "install code-extension " '${CODE_EXT_PKGS}'       "code-ext-pkg alongside curated extension"

# Both are order-65 segments, so both land after `setup elixir` (order 60).
TEST_COUNT=$((TEST_COUNT + 1))
ELIXIR_LINE=$(grep -n '^setup elixir --version' "$boothfile" | head -1 | cut -d: -f1)
EXT_LINE=$(grep -n '^install code-extension' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$ELIXIR_LINE" && -n "$EXT_LINE" && "$EXT_LINE" -gt "$ELIXIR_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: install code-extension comes after setup elixir ... "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: install code-extension comes after setup elixir")
  echo -n "Test ${TEST_COUNT}: install code-extension comes after setup elixir ... "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup elixir line: ${ELIXIR_LINE:-<none>}, install code-extension line: ${EXT_LINE:-<none>}"
fi

finally
