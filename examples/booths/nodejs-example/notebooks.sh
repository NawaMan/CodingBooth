#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Run notebooks without a UI and print each cell with its output.
#   ./notebooks.sh run        hello-js.ipynb and hello-ts.ipynb
#   ./notebooks.sh typecheck  type-error.ipynb — succeeds only if tslab rejects
#                             its deliberate type error, which is the point
set -euo pipefail

cd "$(dirname "$0")"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# show <notebook> [--allow-errors] — execute a copy, then print it as markdown.
show() {
  local notebook="$1"; shift
  echo "=== ${notebook} ==="
  jupyter execute --output="$OUT/${notebook}" "$@" "$notebook" 2>&1 | grep -v '^\[NbClientApp\]' || true
  jupyter nbconvert --to markdown --stdout "$OUT/${notebook}" 2>/dev/null | grep -v '^\s*$'
  echo
}

case "${1:-run}" in
  run)
    show hello-js.ipynb
    show hello-ts.ipynb
    ;;
  typecheck)
    show type-error.ipynb --allow-errors | tee "$OUT/typecheck.txt"
    if grep -q "is not assignable to parameter of type 'number'" "$OUT/typecheck.txt"; then
      echo "✅ tslab type-checked the cell and refused to run it."
    else
      echo "❌ Expected tslab to reject the type error in type-error.ipynb." >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [run|typecheck]" >&2
    exit 2
    ;;
esac
