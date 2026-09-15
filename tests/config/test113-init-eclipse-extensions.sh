#!/bin/bash
# Lombok on `eclipse`, the Eclipse counterpart to lombok-idea (test97's
# idea+lombok case). It stays opt-in the same way: a bare `eclipse` select
# must not pull it in, and when selected it must land after `setup eclipse`
# -- eclipse.ini has to exist before lombok-eclipse patches it. test86 only
# proves lombok-eclipse--setup.sh exists, not that anything can reach it
# through `booth config --select`.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- eclipse+lombok ---
run booth config $prj --no-tui --variant xfce --select "eclipse+lombok"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lombok-eclipse" ''              "eclipse+lombok emits setup lombok-eclipse"

# It has to come after the IDE it patches.
TEST_COUNT=$((TEST_COUNT + 1))
ECLIPSE_LINE=$(grep -n '^setup eclipse' "$boothfile" | head -1 | cut -d: -f1)
LOMBOK_LINE=$(grep -n '^setup lombok-eclipse' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$ECLIPSE_LINE" && -n "$LOMBOK_LINE" && "$LOMBOK_LINE" -gt "$ECLIPSE_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: lombok-eclipse comes after setup eclipse ........... "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: lombok-eclipse comes after setup eclipse")
  echo -n "Test ${TEST_COUNT}: lombok-eclipse comes after setup eclipse ........... "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup eclipse: ${ECLIPSE_LINE:-<none>}, setup lombok-eclipse: ${LOMBOK_LINE:-<none>}"
fi

# --- not auto-selected: Lombok is one library's IDE support, not a default ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "eclipse"
boothfile="$prj/.booth/Boothfile"
TEST_COUNT=$((TEST_COUNT + 1))
if ! grep -q '^setup lombok-eclipse' "$boothfile"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: lombok is opt-in, not auto-selected ................ "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: lombok is opt-in, not auto-selected")
  echo -n "Test ${TEST_COUNT}: lombok is opt-in, not auto-selected ................ "
  echo -e "\033[31mFAILED\033[0m"
fi

finally
