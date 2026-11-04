#!/bin/bash
# A reconfigure keeps a Cache path added to config.toml by hand, even one that a
# template nobody selected also declares -- and still drops a deselected template's.
#
# config.toml holds the selected templates' paths next to the user's own, and booth
# config reads them all back. It used to drop every path that any catalog template
# declared, so a hand-added ~/.zsh_history vanished unless shell-history was
# selected. Only the recorded and the new selection's template paths are dropped now.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

config="$prj/.booth/config.toml"

run booth config $prj --no-tui --select "go"
# By hand: a path the unselected shell-history template also declares.
printf 'cache-files = ["home/coder/.zsh_history"]\n' >> "$config"

run booth config $prj --no-tui --overwrite
assert-line "$config" "cache-files = " '["home/coder/.zsh_history"]' "a hand-added path survives a reconfigure"

# A template's own path still leaves with the template.
run booth config $prj --no-tui --overwrite --select "go/shell-history"
run booth config $prj --no-tui --overwrite --select "go"
check="$prj/deselect-check.txt"
echo "bash_history lines: $(grep -c 'bash_history' "$config")" > "$check"
assert-line "$check" "bash_history lines: " "0" "a deselected template's path is dropped"

finally
