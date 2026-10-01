#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# --engine apple runs Apple container, whose CLI (`container`) is not
# Docker-compatible, so the CLI rewrites each call for it: queries become
# `container ls --all --format json` answered in Go, and run flags with no
# Apple equivalent are dropped (the ones the CLI adds itself) or refused. See
# docs/CONTAINER_SUPPORT.md. The rendering of that JSON is covered by the Go
# unit tests in cli/src/pkg/docker/apple_engine_test.go.

CONFIG="test--engine-apple-config.toml"
trap 'rm -f "$CONFIG"' EXIT

pass() { print_test_result "true"  "$0" "$1" "$2"; }
fail() { print_test_result "false" "$0" "$1" "$2"; echo "Output:"; echo "$3"; exit 1; }

# Lines that start an engine command in the dryrun dump are "<binary> \".
engine_lines() { printf '%s\n' "$1" | grep -E '^(docker|podman|container) \\$' | sort -u | tr -d ' \\' | paste -sd, -; }

OUT=$(run_coding_booth --variant base --dryrun --engine apple 2>/dev/null || true)

# 1. --engine apple runs only the container CLI
if [[ "$(engine_lines "$OUT" || true)" == "container" ]]; then
  pass 1 "--engine apple prints only container commands"
else
  fail 1 "--engine apple prints only container commands" "$OUT"
fi

# 2. the binary name is not an engine name
if ERR=$(run_coding_booth --variant base --dryrun --engine container 2>&1); then
  fail 2 "--engine container is rejected (the engine is apple)" "$ERR"
elif printf '%s\n' "$ERR" | grep -q 'invalid engine "container" (supported: docker, podman, apple)'; then
  pass 2 "--engine container is rejected (the engine is apple)"
else
  fail 2 "--engine container is rejected with a clear message" "$ERR"
fi

# 3. the name check is a JSON listing, not docker's ps --filter/--format
if printf '%s\n' "$OUT" | grep -Eq '^ *ls --all --format json *$' && ! printf '%s\n' "$OUT" | grep -q -- '--filter'; then
  pass 3 "apple queries list JSON instead of ps --filter"
else
  fail 3 "apple queries list JSON instead of ps --filter" "$OUT"
fi

# 4. flags the CLI adds that Apple container lacks are dropped, not passed through
if printf '%s\n' "$OUT" | grep -Eq -- '--add-host|--pull'; then
  fail 4 "apple run has no --add-host / --pull" "$OUT"
else
  pass 4 "apple run has no --add-host / --pull"
fi

# 5. the booth still gets its port and labels
if printf '%s\n' "$OUT" | grep -q -- "-p 127.0.0.1:" && printf '%s\n' "$OUT" | grep -q "cb.managed=true"; then
  pass 5 "apple run keeps the port mapping and lifecycle labels"
else
  fail 5 "apple run keeps the port mapping and lifecycle labels" "$OUT"
fi

# 6. the booth knows which engine started it
if printf '%s\n' "$OUT" | grep -q "BOOTH_ENGINE=apple"; then
  pass 6 "BOOTH_ENGINE=apple is passed into the booth"
else
  fail 6 "BOOTH_ENGINE=apple is passed into the booth" "$OUT"
fi

# 7-8. --dind and --egress are refused up front — before the egress defaults
# write .booth/egress/ into the project
for flag in --dind --egress; do
  num=$([[ "$flag" == "--dind" ]] && echo 7 || echo 8)
  had_booth_dir=$([[ -e .booth ]] && echo yes || echo no)
  if ERR=$(run_coding_booth --variant base --dryrun --engine apple "$flag" --dind-allowed 2>&1); then
    fail "$num" "$flag is refused on engine apple" "$ERR"
  elif [[ "$had_booth_dir" == "no" && -e .booth ]]; then
    rm -rf .booth
    fail "$num" "$flag refusal leaves no .booth/ behind" "$ERR"
  elif printf '%s\n' "$ERR" | grep -q -- "$flag is not supported on engine apple"; then
    pass "$num" "$flag is refused on engine apple"
  else
    fail "$num" "$flag is refused on engine apple with a clear message" "$ERR"
  fi
done

# 9. a run-arg with no Apple equivalent is refused, not silently dropped
printf 'run-args = "--privileged"\n' > "$CONFIG"
if ERR=$(run_coding_booth --config "$CONFIG" --variant base --dryrun --engine apple --privileged-allowed 2>&1); then
  fail 9 "--privileged run-arg is refused on engine apple" "$ERR"
elif printf '%s\n' "$ERR" | grep -q -- "--privileged is not supported on engine apple"; then
  pass 9 "--privileged run-arg is refused on engine apple"
else
  fail 9 "--privileged run-arg is refused on engine apple with a clear message" "$ERR"
fi
