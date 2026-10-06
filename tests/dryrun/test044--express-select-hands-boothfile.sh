#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT

mkdir -p "$PROJECT/.booth"
cat > "$PROJECT/.booth/config.toml" <<'EOF'
port = "12001"
variant = "codeserver"
EOF
printf 'setup not-the-project\n' > "$PROJECT/.booth/Boothfile"

ACTUAL=$(run_coding_booth express --dryrun --code "$PROJECT" \
  --templates-path "$REPO/templates" --select go 2>&1 | strip_ansi || true)

COMPILE=$(printf '%s\n' "$ACTUAL" | grep -F "compiling Boothfile '" || true)
SPEC=$(printf '%s\n' "$COMPILE" | sed -n "s/.*compiling Boothfile '\\(.*\\)\\/Boothfile'.*/\\1/p")

if [[ -n "$SPEC" && "$SPEC" != "$PROJECT/.booth" && "$SPEC" == *"codingbooth-express-"*".booth" ]]; then
  print_test_result "true" "$0" "1" "express --select compiles the spec Boothfile, not the project's"
else
  print_test_result "false" "$0" "1" "express --select compiles the spec Boothfile, not the project's"
  echo "Compile line: ${COMPILE:-<none>}"
  exit 1
fi

if printf '%s\n' "$ACTUAL" | grep -F -- "-v ${SPEC}:/home/coder/code/.booth:ro" >/dev/null \
  && printf '%s\n' "$ACTUAL" | grep -F -- "cb.booth-dir=${SPEC}" >/dev/null \
  && printf '%s\n' "$ACTUAL" | grep -F 'codingbooth-local:' >/dev/null \
  && ! printf '%s\n' "$ACTUAL" | grep -E 'cb\.variant=codeserver|BOOTH_HOST_PORT=12001' >/dev/null; then
  print_test_result "true" "$0" "2" "the run builds that Boothfile and mounts the spec, not the project"
else
  print_test_result "false" "$0" "2" "the run builds that Boothfile and mounts the spec, not the project"
  echo "$ACTUAL"
  exit 1
fi
