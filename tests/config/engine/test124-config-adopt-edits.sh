#!/bin/bash
# booth config reads valid hand edits back instead of refusing them as hand-written:
# an added setting survives a reconfigure (and lands in the header), a comment it
# cannot carry is named before the save, and an edit no flag can produce is still
# refused — with the line that blocks it. No container is started.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "go" --env FOO=1

if [[ ! -f "$prj/.booth/.generated" ]]; then
    skip "booth config did not write .booth/.generated"
fi

# --- A valid edit: a setting booth config could have written, plus a comment ---
cat >> "$prj/.booth/config.toml" <<'EOF'
# the team is in Bangkok
timezone = "Asia/Bangkok"
EOF

(cd "$prj" && booth config --no-tui --overwrite) > "$tmpfile" 2>&1
cat "$tmpfile" >> $log

assert-line "$tmpfile" "Note: .booth/config.toml " \
    "was edited outside booth config; the edits were read back and are kept." \
    "Valid edit is read back, not refused"
assert-line "$tmpfile" "  config.toml:" "5  # the team is in Bangkok" \
    "The comment a save removes is named"
assert-line "$prj/.booth/config.toml" "timezone = " '"Asia/Bangkok"' \
    "The edited setting survives the reconfigure"
assert-line "$prj/.booth/config.toml" "# Configured by: " \
    "booth config --no-tui --overwrite --env FOO=1 --set timezone=Asia/Bangkok --select go" \
    "The edit is now recorded in the header"

ls "$prj/.booth" > "$tmpfile"
echo "bak-files: $(grep -c '\.bak$' "$tmpfile")" > "$tmpfile"
assert-line "$tmpfile" "bak-files: " "0" "Nothing was lost, so nothing is backed up"

# After the save the files are booth config's own again: a plain reconfigure runs.
(cd "$prj" && booth config --no-tui --overwrite --add-env BAR=2) > "$tmpfile" 2>&1
echo "exit: $?" >> "$tmpfile"
cat "$tmpfile" >> $log
assert-line "$tmpfile" "exit: " "0" "The saved files are no longer treated as edited"

# --- An edit no flag can produce: refused, naming the line ---
echo "run echo hand-added" >> "$prj/.booth/Boothfile"

(cd "$prj" && booth config --no-tui --add-env BAZ=3) > "$tmpfile" 2>&1
echo "exit: $?" >> "$tmpfile"
cat "$tmpfile" >> $log

assert-line "$tmpfile" "  - Boothfile " \
    '`run echo hand-added` — no selection or flag produces this line' \
    "An unproducible line is named as the reason"
assert-line "$tmpfile" "Refusing to overwrite " "hand-written files in .booth:" \
    "...and the booth falls back to the hand-written refusal"
assert-line "$tmpfile" "exit: " "1" "The refusal exits non-zero"

finally
