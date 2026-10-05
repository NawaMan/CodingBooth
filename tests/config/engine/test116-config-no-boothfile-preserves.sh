#!/bin/bash
# A booth that sets only config fields (variant, port, mounts) selects no templates,
# so it has no Boothfile — only config.toml. Reconfiguring it must still start from
# its recorded settings: the baseline is read from config.toml's own
# "# Configured by:" header when there is no Boothfile to read it from. Before this,
# the second run below kept only the port and dropped the variant and the mount.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
config="$prj/.booth/config.toml"

# 1) Config fields only — no --select, so no Boothfile is written.
run booth config $prj --no-tui --overwrite --variant terminal --mount /tmp/x:/home/coder/x
assert-line "$config" "variant = " '"terminal"'                               "initial variant is terminal"
assert-line "$config" "run-args = " '["--volume", "/tmp/x:/home/coder/x"]'    "initial mount is recorded"

# 2) Reconfigure only the port — the variant and the mount must survive.
run booth config $prj --no-tui --overwrite --port 10005
assert-line "$config" "port = "     '"10005"'                                 "port was added"
assert-line "$config" "variant = "  '"terminal"'                              "variant preserved without a Boothfile"
assert-line "$config" "run-args = " '["--volume", "/tmp/x:/home/coder/x"]'    "mount preserved without a Boothfile"
finally
