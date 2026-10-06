#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT

mkdir -p "$PROJECT/.booth"
cat > "$PROJECT/.booth/config.toml" <<'EOF'
port = "12001"
variant = "codeserver"
EOF
cat > "$PROJECT/.booth/default--config.toml" <<'EOF'
port = "13001"
EOF
printf 'SECRET=from-project\n' > "$PROJECT/.booth/.env"

BEFORE="$(cksum "$PROJECT/.booth/config.toml")"

ACTUAL=$(run_coding_booth express --dryrun --code "$PROJECT" | strip_ansi || true)

MOUNT=$(printf '%s\n' "$ACTUAL" | grep -F '/home/coder/code/.booth:ro' || true)
if [[ -n "$MOUNT" ]] && ! printf '%s\n' "$MOUNT" | grep -F "$PROJECT/.booth:" >/dev/null; then
  print_test_result "true" "$0" "1" "express mounts its own spec, not the project .booth"
else
  print_test_result "false" "$0" "1" "express mounts its own spec, not the project .booth"
  echo "Mount line: ${MOUNT:-<none>}"
  exit 1
fi

if printf '%s\n' "$ACTUAL" | grep -E 'cb\.variant=codeserver|HOST_PORT:[[:space:]]+12001|HOST_PORT:[[:space:]]+13001|BOOTH_HOST_PORT=12001|BOOTH_HOST_PORT=13001' >/dev/null; then
  print_test_result "false" "$0" "2" "express does not apply the project port or variant"
  echo "$ACTUAL"
  exit 1
fi
print_test_result "true" "$0" "2" "express does not apply the project port or variant"

AFTER="$(cksum "$PROJECT/.booth/config.toml")"
if [[ "$BEFORE" == "$AFTER" ]]; then
  print_test_result "true" "$0" "3" "express does not rewrite the project config"
else
  print_test_result "false" "$0" "3" "express does not rewrite the project config"
  exit 1
fi
