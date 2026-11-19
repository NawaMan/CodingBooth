#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for the AWS env-credentials example.
#
# Needs AWS credentials in the host ENVIRONMENT (not ~/.aws files):
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION or AWS_DEFAULT_REGION.
# Without them it exits 77, which run-example-tests.sh reports as SKIPPED
# (it also skips before calling this, from .cb-tests/requires-env.txt).
#

set -euo pipefail

missing=()
[[ -n "${AWS_ACCESS_KEY_ID:-}"     ]] || missing+=(AWS_ACCESS_KEY_ID)
[[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || missing+=(AWS_SECRET_ACCESS_KEY)
[[ -n "${AWS_REGION:-}${AWS_DEFAULT_REGION:-}" ]] || missing+=("AWS_REGION|AWS_DEFAULT_REGION")
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "SKIP: the host environment has no ${missing[*]}."
    echo "      This example takes AWS credentials from environment variables only."
    exit 77
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

cd "$SCRIPT_DIR/.."

"$BOOTH" --port "${CB_PORT:-50022}" -- ./.cb-tests/inBooth--run-all-tests.sh
