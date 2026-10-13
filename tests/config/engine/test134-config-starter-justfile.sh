#!/bin/bash
# booth config adds the starter Justfile (the one `booth just-init` writes) on a
# project's first configure — no .booth/Boothfile and no .booth/config.toml yet —
# and only when the project has no Justfile of its own. A reconfigure never
# recreates one the user deleted, and never touches one they already had.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
status="$prj/.status"

# state: present/absent of each name, and whether what is there is the starter,
# one line each, for assert-line to read. "starter:" is always reported, because
# on a case-insensitive filesystem (macOS) it is the only line that can answer
# the question — see case 3.
function state() {
    for f in Justfile justfile; do
        if [[ -e "$prj/$f" ]]; then echo "$f: present"; else echo "$f: absent"; fi
    done > "$status"
    if cmp -s "$prj/Justfile" "$_repo_root/docs/just/Justfile"; then
        echo "starter: same"  >> "$status"
    else
        echo "starter: other" >> "$status"
    fi
}

# 1) First configure: the starter appears.
run booth config $prj --no-tui --overwrite --variant terminal
state
assert-line "$status" "Justfile: " "present"                       "first configure writes the starter Justfile"
assert-line "$status" "starter: "  "same"                          "it is docs/just/Justfile"

# 2) Reconfigure after the user deleted it: it stays deleted.
rm -f "$prj/Justfile"
run booth config $prj --no-tui --overwrite --port 10005
state
assert-line "$status" "Justfile: " "absent"                        "a reconfigure does not recreate it"

# 3) First configure of a project with its own justfile: left untouched, no starter beside it.
rm -Rf "$prj"; mkdir -p "$prj"
printf 'mine:\n    echo mine\n' > "$prj/justfile"
run booth config $prj --no-tui --overwrite --variant terminal
state
# By content, not by name: macOS is case-insensitive, so `-e $prj/Justfile`
# finds the project's own lowercase justfile and "absent" can never hold there,
# however right booth was. A starter would be docs/just/Justfile; this is not.
assert-line "$status" "starter: " "other"                          "no starter beside an existing justfile"
assert-line "$prj/justfile" "mine:" ""                             "the existing justfile is untouched"
finally
