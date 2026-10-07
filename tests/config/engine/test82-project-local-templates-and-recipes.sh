#!/bin/bash
# Project-local templates (.booth/templates) and recipes (.booth/recipes).
# Uses --dryrun so Docker is not required.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# --- Local template: one flat file, .booth/templates/<name>.toml ---
mkdir -p "$prj/.booth/templates"
cat > "$prj/.booth/templates/myapp.toml" <<'EOF'
display-name = "My App"
display-disc = "Project-local template"
primary = true

[segments]
Boothfile = """
setup myapp
"""
EOF

run booth config "$prj" --no-tui --dryrun --select myapp

assert-line "$log" "setup " "myapp" "Local template myapp appears in dryrun Boothfile"

# --- Flat extension: <template>--<ext>--extension.toml, selected as parent+ext ---
cat > "$prj/.booth/templates/myapp--widget--extension.toml" <<'EOF'
[segments]
Boothfile = """
setup myapp-widget
"""
EOF

run booth config "$prj" --no-tui --dryrun --select myapp+widget

assert-line "$log" "setup myapp-widget" "" "Flat extension myapp+widget appears in dryrun Boothfile"

# --- Local template overrides stock go ---
cat > "$prj/.booth/templates/go.toml" <<'EOF'
display-name = "Go (local)"
display-disc = "Overrides stock go"
primary = true

[segments]
Boothfile = """
# local-go-override
setup go 9.9.9
"""
EOF

# Warnings go to stderr; run() merges them into the log.
run booth config "$prj" --no-tui --dryrun --select go

assert-line "$log" "Warning: project template " "\"go\" overrides built-in (category \"languages\" → \"project\")" \
  "Override of stock go prints a warning"
assert-line "$log" "# local-go-override" "" "Overridden go template content is used"

# --- Project recipe bare name ---
mkdir -p "$prj/.booth/recipes"
cat > "$prj/.booth/recipes/stack.recipe" <<'EOF'
# stack for the app
myapp
EOF

recipe_out="$prj/recipe.txt"
booth config "$prj" --no-tui --dryrun --select @stack >"$recipe_out" 2>&1 || true

assert-line "$recipe_out" "setup " "myapp" "A # comment in @stack is ignored and myapp is still selected"

# --- Missing recipe hard-errors ---
if booth config "$prj" --no-tui --dryrun --select @no-such-recipe >>"$log" 2>&1; then
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("missing recipe should fail")
  echo -e "Test missing recipe ................................ \033[31mFAILED\033[0m (expected non-zero exit)"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: missing recipe hard-errors ..................... \033[32mPASSED\033[0m"
  echo "recipe not found" >>"$log"
fi

# --- Unknown local template hard-errors ---
if booth config "$prj" --no-tui --dryrun --select not-a-template >>"$log" 2>&1; then
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("unknown template should fail")
  echo -e "Test unknown template .............................. \033[31mFAILED\033[0m (expected non-zero exit)"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: unknown template hard-errors ................... \033[32mPASSED\033[0m"
fi

finally
