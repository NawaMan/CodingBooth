#!/bin/bash
# A project-local template is one file, .booth/templates/<name>.toml:
# no directory, no meta.toml, no display keys.
# Every local template lists under "This project".
# Uses no Docker: --dryrun, a --no-tui write, and `template list`.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# --- Two flat files; one is nothing but segments + an inline setup ---
mkdir -p "$prj/.booth/templates"
cat > "$prj/.booth/templates/native-libs.toml" <<'EOF'
[segments]
"Boothfile--45" = """
install apt libc++1
setup native-libs
"""

[files.setups]
"native-libs--setup.sh" = """
#!/usr/bin/env bash
set -Eeuo pipefail
ldconfig
"""
EOF
cat > "$prj/.booth/templates/seed-data.toml" <<'EOF'
[segments]
Boothfile = """
setup seed-data
"""
EOF

out="$prj/dry.txt"
run booth config "$prj" --no-tui --dryrun --select native-libs/seed-data
booth config "$prj" --no-tui --dryrun --select native-libs/seed-data >"$out" 2>&1 || true
assert-line "$out" "install apt " "libc++1" "Meta-less template emits its Boothfile segment"
assert-line "$out" "setup seed-data" "" "A second flat file loads beside the first"

# --- A real write lands the inline setup in .booth/setups/ ---
run booth config "$prj" --no-tui --overwrite --select native-libs
head -1 "$prj/.booth/setups/native-libs--setup.sh" >"$prj/setup-head.txt" 2>/dev/null || true
assert-line "$prj/setup-head.txt" "#!/usr/bin/env " "bash" "[files.setups] writes .booth/setups/native-libs--setup.sh"

# --- Both list under "This project", shown by default (primary defaults to true) ---
(cd "$prj" && booth template list) >"$prj/list.txt" 2>&1 || true
head -1 "$prj/list.txt" >"$prj/list-first.txt"
assert-line "$prj/list-first.txt" "This project" "" "Project category is first and named by default"
awk 'NR > 1 && NF == 0 { exit } NR > 1 { print $1 }' "$prj/list.txt" | sort >"$prj/list-project.txt"
assert-line "$prj/list-project.txt" "native-libs" "" "native-libs lists under This project without --full"
assert-line "$prj/list-project.txt" "seed-data" "" "seed-data lists under This project"

# --- display-name falls back to the template name ---
(cd "$prj" && booth template show native-libs) >"$prj/show.txt" 2>&1 || true
assert-line "$prj/show.txt" "Category:" "    project" "template show reports the project category"
head -1 "$prj/show.txt" >"$prj/show-first.txt"
assert-line "$prj/show-first.txt" "native-libs " "(native-libs)" "template show titles it by its name"

# --- A directory under .booth/templates/ is an error ---
mkdir -p "$prj/.booth/templates/nested"
if booth config "$prj" --no-tui --dryrun --select native-libs >>"$log" 2>&1; then
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("a directory under .booth/templates should fail")
  echo -e "Test directory under templates ..................... \033[31mFAILED\033[0m (expected non-zero exit)"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: a directory under .booth/templates fails ..... \033[32mPASSED\033[0m"
fi
if grep -q 'is a directory' "$log"; then
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: directory error names the flat file .......... \033[32mPASSED\033[0m"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("directory error should say it is a directory")
  echo -e "Test directory error text .......................... \033[31mFAILED\033[0m"
fi
rmdir "$prj/.booth/templates/nested"

# --- An extension file with no parent prefix is an error ---
cat > "$prj/.booth/templates/fancy--extension.toml" <<'EOF'
[segments]
Boothfile = """
setup fancy
"""
EOF
if booth config "$prj" --no-tui --dryrun --select native-libs >>"$log" 2>&1; then
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("an extension file without a parent prefix should fail")
  echo -e "Test extension without parent ...................... \033[31mFAILED\033[0m (expected non-zero exit)"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: extension without a parent prefix fails .... \033[32mPASSED\033[0m"
fi
if grep -q 'needs a parent prefix' "$log"; then
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: extension error asks for the parent name ... \033[32mPASSED\033[0m"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("extension error should ask for a parent prefix")
  echo -e "Test extension error text .......................... \033[31mFAILED\033[0m"
fi

finally
