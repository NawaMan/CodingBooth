#!/bin/bash
# Three extensions on `idea`: Lombok (the IntelliJ counterpart to the
# lombok-eclipse setup), which stays opt-in, and skipping the first-run
# prompts / opening the project automatically, which commit 365140ea made
# auto-select (jetbrains-import-project--extension.toml / skip-first-run--
# extension.toml both carry auto-select = true) — a bare `idea` selection now
# emits both without being asked. Lombok not auto-selecting, and the
# auto-selected pair still showing up on a bare `idea`, is what would silently
# break if an extension stopped being selectable: test86 only proves the
# setup script exists, not that anything can reach it.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- idea+lombok ---
run booth config $prj --no-tui --variant xfce --select "java/idea+lombok"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lombok-idea" ''              "idea+lombok emits setup lombok-idea"

# It has to come after the IDE it installs into.
TEST_COUNT=$((TEST_COUNT + 1))
IDEA_LINE=$(grep -n '^setup idea' "$boothfile" | head -1 | cut -d: -f1)
LOMBOK_LINE=$(grep -n '^setup lombok-idea' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$IDEA_LINE" && -n "$LOMBOK_LINE" && "$LOMBOK_LINE" -gt "$IDEA_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: lombok-idea comes after setup idea ................. "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: lombok-idea comes after setup idea")
  echo -n "Test ${TEST_COUNT}: lombok-idea comes after setup idea ................. "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup idea: ${IDEA_LINE:-<none>}, setup lombok-idea: ${LOMBOK_LINE:-<none>}"
fi

# --- not auto-selected: Lombok is one library's IDE support, not a default ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "java/idea"
boothfile="$prj/.booth/Boothfile"
TEST_COUNT=$((TEST_COUNT + 1))
if ! grep -q '^setup lombok-idea' "$boothfile"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: lombok is opt-in, not auto-selected ................ "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: lombok is opt-in, not auto-selected")
  echo -n "Test ${TEST_COUNT}: lombok is opt-in, not auto-selected ................ "
  echo -e "\033[31mFAILED\033[0m"
fi

# --- idea+skip-first-run ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea+skip-first-run"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup jetbrains-first-run" ''      "idea+skip-first-run emits setup jetbrains-first-run"

# --- and it keeps arriving unasked on a bare `idea` — auto-select = true since
#     365140ea, guarding a decision, not just a default: an extension that
#     silently stopped auto-selecting would leave a fresh IDE booth back to
#     clicking through first-run modals with no test noticing. ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup jetbrains-first-run" ''      "first-run seeding auto-selects on a bare idea"

# --- both together, alongside the generic escape hatch left empty (java-example's shape) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "java/idea+lombok+skip-first-run/jetbrains-plugin-pkg"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lombok-idea" ''              "lombok alongside skip-first-run"
assert-line "$boothfile" "setup jetbrains-first-run" ''      "skip-first-run alongside lombok"
assert-line "$boothfile" "arg JETBRAINS_PLUGIN_PKGS=" ''     "generic plugin list present but empty"

finally
