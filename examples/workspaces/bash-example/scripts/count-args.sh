#!/usr/local/bin/bash-3.2
# Count arguments with the empty-array form that Bash 3.2 accepts under set -u.
# macOS ships Bash 3.2 as /bin/bash. "${items[@]}" on an empty array is an
# error there. ${items[@]+"${items[@]}"} expands to nothing instead.
set -u
items=("$@")
count=0
for _ in ${items[@]+"${items[@]}"}; do
  count=$((count + 1))
done
echo "count=${count}"
