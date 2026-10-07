#!/bin/bash
# A project-local template needs only its template.toml: no meta.toml, no display keys.
# Every local template, whatever folder it sits in, lists under "This project".
# Uses no Docker: --dryrun, a --no-tui write, and `template list`.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# --- No meta.toml anywhere; one template is nothing but segments + an inline setup ---
mkdir -p "$prj/.booth/templates/project/native-libs" "$prj/.booth/templates/tools/seed-data"
cat > "$prj/.booth/templates/project/native-libs/template.toml" <<'EOF'
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
# A folder other than project/ — still the project category.
cat > "$prj/.booth/templates/tools/seed-data/template.toml" <<'EOF'
[segments]
Boothfile = """
setup seed-data
"""
EOF

out="$prj/dry.txt"
run booth config "$prj" --no-tui --dryrun --select native-libs/seed-data
booth config "$prj" --no-tui --dryrun --select native-libs/seed-data >"$out" 2>&1 || true
assert-line "$out" "install apt " "libc++1" "Meta-less template emits its Boothfile segment"
assert-line "$out" "setup seed-data" "" "Template in a non-project folder loads without meta.toml"

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
assert-line "$prj/list-project.txt" "seed-data" "" "seed-data (tools/ folder) lists under This project"

# --- display-name falls back to the template name ---
(cd "$prj" && booth template show native-libs) >"$prj/show.txt" 2>&1 || true
assert-line "$prj/show.txt" "Category:" "    project" "template show reports the project category"
head -1 "$prj/show.txt" >"$prj/show-first.txt"
assert-line "$prj/show-first.txt" "native-libs " "(native-libs)" "template show titles it by its name"

finally
