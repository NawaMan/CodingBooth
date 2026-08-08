#!/bin/bash
# idea+jdk-sdk: registering the image's JDKs as SDKs in IntelliJ. Auto-selected,
# because an IDE with no SDK opens every Java project unresolved.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- auto-selected with the IDE, no extension named ---
run booth config $prj --no-tui --variant xfce --select "java/idea"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup jetbrains-jdk" ''            "jetbrains-jdk is auto-selected with idea"

# --- it lands after both the JDK and the IDE, which is what makes it work at all:
#     it reads the installed JDKs and the installed IDEs to know what to write ---
TEST_COUNT=$((TEST_COUNT + 1))
JDK_LINE=$(grep -n '^setup jdk' "$boothfile" | head -1 | cut -d: -f1)
IDEA_LINE=$(grep -n '^setup idea' "$boothfile" | head -1 | cut -d: -f1)
SDK_LINE=$(grep -n '^setup jetbrains-jdk' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$JDK_LINE" && -n "$IDEA_LINE" && -n "$SDK_LINE" \
      && "$SDK_LINE" -gt "$JDK_LINE" && "$SDK_LINE" -gt "$IDEA_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: jetbrains-jdk comes after setup jdk and setup idea .. "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: jetbrains-jdk comes after setup jdk and setup idea")
  echo -n "Test ${TEST_COUNT}: jetbrains-jdk comes after setup jdk and setup idea .. "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup jdk: ${JDK_LINE:-<none>}, setup idea: ${IDEA_LINE:-<none>}, setup jetbrains-jdk: ${SDK_LINE:-<none>}"
fi

# --- selecting the IDE without Java stays valid: the setup skips at build time ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup jetbrains-jdk" ''            "jetbrains-jdk still emitted without a JDK selected"

# --- and it can be turned off, for anyone who manages their own SDK table ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "java/idea~jdk-sdk"
boothfile="$prj/.booth/Boothfile"
TEST_COUNT=$((TEST_COUNT + 1))
if ! grep -q '^setup jetbrains-jdk' "$boothfile"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: jdk-sdk can be deselected ......................... "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: jdk-sdk can be deselected")
  echo -n "Test ${TEST_COUNT}: jdk-sdk can be deselected ......................... "
  echo -e "\033[31mFAILED\033[0m"
  grep -n 'jetbrains-jdk' "$boothfile" | sed 's/^/    /'
fi

finally
