#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Test for the share example: the notes app shared with cloudflared-share / ngrok-share.
# Needs internet access (the public URL is fetched back). The ngrok live share
# runs only when NGROK_AUTHTOKEN is set on the host; the rest always runs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

cd "$SCRIPT_DIR/.."

"$BOOTH" --port "${CB_PORT:-50911}" -- ./.cb-tests/inBooth--run-all-tests.sh
