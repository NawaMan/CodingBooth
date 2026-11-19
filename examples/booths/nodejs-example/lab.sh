#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Serve JupyterLab on the notebook port (18888). That port is not published to
# the host, so open it through the booth port's proxy instead.
set -euo pipefail

cd "$(dirname "$0")"
PORT="${NOTEBOOK_PORT:-18888}"
HOST_PORT="${BOOTH_HOST_PORT:-10000}"   # resolved; BOOTH_PORT may be NEXT or RANDOM

echo "Open http://localhost:${HOST_PORT}/proxy/${PORT}/lab — then hello-ts.ipynb, or type-error.ipynb."
echo "Ctrl+C stops it."
exec start-notebook "$PORT"
