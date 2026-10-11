#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: {name} in a run-args volume source becomes the booth name; {project}
#       stays the project (folder) name
#
# The service templates mount <service>-{name} (booth-pgdata-{name}). A booth's
# default name is its folder, so a single booth keeps one volume per project; a
# second booth of the same folder has another name (--name, '{project}-{port}',
# or the automatic <project>-<port>) and so its own volume. config.toml keeps the
# placeholder; the run expands it.
#
# Test 1: default booth       -> -v booth-pgdata-volproj:...
# Test 2: --name other        -> -v booth-pgdata-other:...
# Test 3: --name '{project}-{port}' --port 7654 -> -v booth-pgdata-volproj-7654:...
# Test 4: {project} stays the folder name under --name other
# Test 5: no literal {name} or {project} reaches the docker command
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/volproj/.booth"
cat > "$WORK/volproj/.booth/config.toml" <<'TOML'
run-args = [
    "-v", "booth-pgdata-{name}:/var/lib/postgresql",
    "-v", "shared-cache-{project}:/home/coder/.cache",
]
TOML

FAILED=0

expect_mount() { # test-number, description, expected -v spec, run args...
    local num="$1" desc="$2" want="$3"
    shift 3
    local actual
    actual=$(run_coding_booth --dryrun --code "$WORK/volproj" --variant base "$@" -- true 2>&1 || true)
    if echo "$actual" | grep -qF -- "-v $want"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "$actual" | grep -E -- 'pgdata|shared-cache' | head -5
        FAILED=$((FAILED + 1))
    fi
}

expect_mount 1 "Default booth runs booth-pgdata-{name} as booth-pgdata-volproj" \
    "booth-pgdata-volproj:/var/lib/postgresql"
expect_mount 2 "--name other runs booth-pgdata-{name} as booth-pgdata-other" \
    "booth-pgdata-other:/var/lib/postgresql" --name other
expect_mount 3 "--name '{project}-{port}' runs booth-pgdata-{name} as booth-pgdata-volproj-7654" \
    "booth-pgdata-volproj-7654:/var/lib/postgresql" --port 7654 --name '{project}-{port}'
expect_mount 4 "{project} stays the folder name under --name other" \
    "shared-cache-volproj:/home/coder/.cache" --name other

ACTUAL=$(run_coding_booth --dryrun --code "$WORK/volproj" --variant base --name other -- true 2>&1 || true)
if ! echo "$ACTUAL" | grep -qE -- '-v [^ ]*\{(name|project)\}'; then
  print_test_result "true" "$0" "5" "No literal {name} or {project} reaches a docker -v"
else
  print_test_result "false" "$0" "5" "A literal {name} or {project} reached a docker -v"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
