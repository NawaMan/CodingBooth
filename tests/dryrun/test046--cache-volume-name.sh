#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth-cache-* named volume is passed through to docker run
#
# Package-download caches are machine-wide named volumes (no {project}, no host
# path). Dry-run must keep the -v spec. A missing host folder must not drop it,
# because it is not a bind mount.
#
# Test 1: -v booth-cache-gomod:... reaches the docker command
# Test 2: the Go cache env pin reaches the docker command
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cacheproj/.booth"
cat > "$WORK/cacheproj/.booth/config.toml" <<'EOF'
run-args = [
    "-e", "GOMODCACHE=/home/coder/go/pkg/mod",
    "-v", "booth-cache-gomod:/home/coder/go/pkg/mod",
]
EOF

FAILED=0
ACTUAL=$(run_coding_booth --dryrun --code "$WORK/cacheproj" --variant base -- true 2>&1)

if echo "$ACTUAL" | grep -qF -- "-v booth-cache-gomod:/home/coder/go/pkg/mod"; then
  print_test_result "true" "$0" "1" "booth-cache-gomod is passed to docker run"
else
  print_test_result "false" "$0" "1" "booth-cache-gomod should be passed to docker run"
  echo "$ACTUAL" | grep -- 'booth-cache' | head -5
  FAILED=$((FAILED + 1))
fi

# docker arg quoting wraps values that contain '='.
if echo "$ACTUAL" | grep -qF -- "'GOMODCACHE=/home/coder/go/pkg/mod'"; then
  print_test_result "true" "$0" "2" "GOMODCACHE pin is passed to docker run"
else
  print_test_result "false" "$0" "2" "GOMODCACHE pin should be passed to docker run"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
