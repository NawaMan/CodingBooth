#!/bin/bash
# Reconfiguring a booth must not grow its cache lists.
#
# A cache entry reaches the regenerated config.toml from two directions: it is
# read back out of the existing config.toml, and it is also in the "Configured
# by" header as a `--set cache-files=...`, which is applied on top. Both are
# right on their own; together they wrote the entry twice, and every further
# reconfigure added another copy.
source "$(dirname "$0")/test-helpers--source.sh"

begin

config="$prj/.booth/config.toml"

run booth config $prj --no-tui --select "go" --set cache-files=go.sum --set cache-dirs=vendor
assert-line "$config" "cache-files = " '["go.sum"]' "seed writes one cache-files entry"
assert-line "$config" "cache-dirs = "  '["vendor"]' "seed writes one cache-dirs entry"

# Reconfigure twice: once is enough to duplicate, twice shows it compounding.
run booth config $prj --no-tui --overwrite
run booth config $prj --no-tui --overwrite

assert-line "$config" "cache-files = " '["go.sum"]' "cache-files stays a single entry across reconfigures"
assert-line "$config" "cache-dirs = "  '["vendor"]' "cache-dirs stays a single entry across reconfigures"

finally
