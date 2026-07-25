#!/bin/bash
# Phase 2 binary companions: csharp+dotnet-pkg / install dotnet tools.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- single tool ---
run booth config $prj --no-tui --select "csharp+dotnet-pkg:dotnet-ef"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg DOTNET_PKGS=" 'dotnet-ef'  "DOTNET_PKGS arg for single tool"
assert-line "$boothfile" "install dotnet " '${DOTNET_PKGS}'  "install dotnet line"
assert-line "$boothfile" "setup dotnet --channel " '${DOTNET_CHANNEL}'  "csharp parent selected"

# --- multiple tools (order may be normalized by the config writer) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "csharp+dotnet-pkg:dotnet-ef,csharpier"
boothfile="$prj/.booth/Boothfile"
FOUND_PKGS="$(grep '^arg DOTNET_PKGS=' "$boothfile" | head -1 | sed 's/^arg DOTNET_PKGS=//')"
TEST_COUNT=$((TEST_COUNT + 1))
if echo ",${FOUND_PKGS}," | grep -q ',dotnet-ef,' && echo ",${FOUND_PKGS}," | grep -q ',csharpier,'; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: DOTNET_PKGS arg for multiple tools ................ "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: DOTNET_PKGS arg for multiple tools")
  echo -n "Test ${TEST_COUNT}: DOTNET_PKGS arg for multiple tools ................ "
  echo -e "\033[31mFAILED\033[0m"
  echo "  FOUND: arg DOTNET_PKGS=${FOUND_PKGS}"
fi

# --- version pin via package@version ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "csharp+dotnet-pkg:dotnet-ef@8.0.11"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg DOTNET_PKGS=" 'dotnet-ef@8.0.11'  "DOTNET_PKGS version pin"

# --- also available under languages/dotnet ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "dotnet+dotnet-pkg:dotnet-ef"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "install dotnet " '${DOTNET_PKGS}'  "dotnet parent + dotnet-pkg"

finally
