#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# First-five-minutes Floci demo: wait for the local AWS emulator, create a
# bucket, put a file, read it back.
set -euo pipefail

BUCKET="${FLOCI_DEMO_BUCKET:-codingbooth-demo}"
HELLO="${TMPDIR:-/tmp}/hello-floci.txt"
BACK="${TMPDIR:-/tmp}/hello-floci-back.txt"

echo "Waiting for Floci on ${AWS_ENDPOINT_URL:-http://localhost:4566} ..."
if ! floci wait --timeout 90s; then
  echo "❌ Floci did not become ready. Is autostart on, and is Docker (dind) up?" >&2
  echo "   Try: floci start && floci wait" >&2
  exit 1
fi

# Refresh endpoint/keys from the running emulator (port may differ from default).
eval "$(floci env)"

printf '%s\n' "hello from floci" > "$HELLO"

aws s3 mb "s3://${BUCKET}" 2>/dev/null || true
aws s3 cp "$HELLO" "s3://${BUCKET}/hello-floci.txt"
aws s3 cp "s3://${BUCKET}/hello-floci.txt" "$BACK"

echo "---"
echo "Bucket: s3://${BUCKET}"
aws s3 ls "s3://${BUCKET}/"
echo "---"
echo -n "Downloaded object: "
cat "$BACK"

if ! grep -qx "hello from floci" "$BACK"; then
  echo "❌ Downloaded object did not match what we uploaded." >&2
  exit 1
fi

echo "✅ Floci round-trip succeeded."
