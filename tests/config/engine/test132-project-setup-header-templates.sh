#!/bin/bash
# A project setup with a `# cb-template:` header is selectable without a template.toml.
# Uses --dryrun so Docker is not required.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

mkdir -p "$prj/.booth/setups"

# --- Header makes the setup a template; params pass positionally ---
cat > "$prj/.booth/setups/greet--setup.sh" <<'EOF'
#!/bin/bash
# cb-template: Greeting
# cb-disc:     Writes a greeting file
# cb-band:     90
# cb-param:    GREET_WHO default=world suggests=world,booth
set -e
echo "hello $1" > /etc/greeting
EOF

# A script without the marker stays invisible.
cat > "$prj/.booth/setups/helper--setup.sh" <<'EOF'
#!/bin/bash
# cb-version: 1.0.0
set -e
EOF

# Each dryrun gets its own output: assert-line matches the first line in a file.
dry() {
  out="$prj/dry-$1.txt"
  shift
  run booth config "$prj" --no-tui --dryrun --select "$@"
  booth config "$prj" --no-tui --dryrun --select "$@" >"$out" 2>&1 || true
}

dry default greet
assert-line "$out" "setup greet " '${GREET_WHO}' "Header template emits setup greet with its param"
assert-line "$out" "arg GREET_WHO=" "world" "Header param default becomes the arg pin"

dry pinned greet:booth
assert-line "$out" "arg GREET_WHO=" "booth" "Positional value maps onto the header param"

# cb-band 90 puts greet after obsidian (band 60), though "greet" sorts first by name.
dry band "greet/obsidian"
grep -E '^setup (greet|obsidian)' "$out" | head -1 >"$prj/first-setup.txt"
assert-line "$prj/first-setup.txt" "setup " 'obsidian ${OBSIDIAN_VERSION}' "cb-band 90 orders greet after a band-60 template"

# --- Marker-less script is not a template ---
if booth config "$prj" --no-tui --dryrun --select helper >>"$log" 2>&1; then
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("helper without cb-template should not be selectable")
  echo -e "Test helper without marker ......................... \033[31mFAILED\033[0m (expected non-zero exit)"
else
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "Test ${TEST_COUNT}: setup without cb-template is not a template ..... \033[32mPASSED\033[0m"
fi

# --- A template.toml of the same name wins, with a warning ---
mkdir -p "$prj/.booth/templates/project/greet"
cat > "$prj/.booth/templates/project/meta.toml" <<'EOF'
display-name = "This project"
order = 0
EOF
cat > "$prj/.booth/templates/project/greet/template.toml" <<'EOF'
display-name = "Greeting (explicit)"
primary = true

[segments]
Boothfile = """
# explicit-greet
setup greet everyone
"""
EOF

dry explicit greet
assert-line "$out" "Warning: project template " "\"greet\" (category \"project\") overrides the cb-template header in .booth/setups/greet--setup.sh" \
  "template.toml beating a header prints a warning"
assert-line "$out" "# explicit-greet" "" "template.toml content is used over the header"

finally
