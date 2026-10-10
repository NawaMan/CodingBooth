#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: {project} in a run-args volume source becomes the project name
#
# The service templates mount <service>-{project} (booth-pgdata-{project}) so each
# project gets its own data volume instead of one shared by the whole machine.
# config.toml keeps the placeholder; the run expands it from the project folder.
#
# Test 1: -v booth-pgdata-{project}:... runs as -v booth-pgdata-<folder>:...
# Test 2: no literal {project} reaches the docker command
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/volproj/.booth"
cat > "$WORK/volproj/.booth/config.toml" <<'EOF'
run-args = ["-v", "booth-pgdata-{project}:/var/lib/postgresql"]
EOF

FAILED=0
ACTUAL=$(run_coding_booth --dryrun --code "$WORK/volproj" --variant base -- true 2>&1)

if echo "$ACTUAL" | grep -qF -- "-v booth-pgdata-volproj:/var/lib/postgresql"; then
  print_test_result "true" "$0" "1" "booth-pgdata-{project} runs as booth-pgdata-volproj"
else
  print_test_result "false" "$0" "1" "booth-pgdata-{project} should run as booth-pgdata-volproj"
  echo "$ACTUAL" | grep -- 'pgdata' | head -5
  FAILED=$((FAILED + 1))
fi

if ! echo "$ACTUAL" | grep -qF "{project}"; then
  print_test_result "true" "$0" "2" "No literal {project} reaches the docker command"
else
  print_test_result "false" "$0" "2" "A literal {project} reached the docker command"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
