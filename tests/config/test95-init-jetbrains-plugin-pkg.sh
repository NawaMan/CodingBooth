#!/bin/bash
# jetbrains-plugin-pkg: arbitrary JetBrains IDE plugins by marketplace id, baked into
# the image, alongside the runtime-install `setup jetbrains-plugin`.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- single plugin id ---
run booth config $prj --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg JETBRAINS_PLUGIN_PKGS=" 'IdeaVIM'                     "JETBRAINS_PLUGIN_PKGS arg for single id"
assert-line "$boothfile" "install jetbrains-plugin " '${JETBRAINS_PLUGIN_PKGS}'     "install jetbrains-plugin line"

# --- numeric id: the form to use when the xmlId has a space ("Lombook Plugin") ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:6317"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg JETBRAINS_PLUGIN_PKGS=" '6317'                        "JETBRAINS_PLUGIN_PKGS arg for numeric id"

# --- multiple ids (order may be normalized by the config writer) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM,6317"
boothfile="$prj/.booth/Boothfile"
FOUND_PLUGINS="$(grep '^arg JETBRAINS_PLUGIN_PKGS=' "$boothfile" | head -1 | sed 's/^arg JETBRAINS_PLUGIN_PKGS=//')"
TEST_COUNT=$((TEST_COUNT + 1))
if echo ",${FOUND_PLUGINS}," | grep -q ',IdeaVIM,' && echo ",${FOUND_PLUGINS}," | grep -q ',6317,'; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: JETBRAINS_PLUGIN_PKGS arg for multiple ids ........ "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: JETBRAINS_PLUGIN_PKGS arg for multiple ids")
  echo -n "Test ${TEST_COUNT}: JETBRAINS_PLUGIN_PKGS arg for multiple ids ........ "
  echo -e "\033[31mFAILED\033[0m"
  echo "  FOUND: arg JETBRAINS_PLUGIN_PKGS=${FOUND_PLUGINS}"
fi

# --- version pin via id@version ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM@2.31.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg JETBRAINS_PLUGIN_PKGS=" 'IdeaVIM@2.31.0'              "JETBRAINS_PLUGIN_PKGS version pin"

# --- the plugins are installed after the IDE that receives them ---
# `setup idea` is an order-60 segment and `install jetbrains-plugin` an order-70 one,
# so the ordering is what makes the install find an IDE at all.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea/pycharm/jetbrains-plugin-pkg:IdeaVIM"
boothfile="$prj/.booth/Boothfile"
TEST_COUNT=$((TEST_COUNT + 1))
IDEA_LINE=$(grep -n '^setup idea' "$boothfile" | head -1 | cut -d: -f1)
PLUGIN_LINE=$(grep -n '^install jetbrains-plugin' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$IDEA_LINE" && -n "$PLUGIN_LINE" && "$PLUGIN_LINE" -gt "$IDEA_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: install jetbrains-plugin comes after setup idea ... "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: install jetbrains-plugin comes after setup idea")
  echo -n "Test ${TEST_COUNT}: install jetbrains-plugin comes after setup idea ... "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup idea line: ${IDEA_LINE:-<none>}, install jetbrains-plugin line: ${PLUGIN_LINE:-<none>}"
fi

# --- the older runtime-install path still selects independently ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --variant xfce --select "idea"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup idea" ''                                            "idea alone still configures"

finally
