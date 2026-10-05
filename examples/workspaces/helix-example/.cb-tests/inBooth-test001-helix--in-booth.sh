#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

echo "=== Helix version, runtime, shared theme ==="
ver="$(hx --version 2>&1 || true)"
echo "$ver" | grep -q "25.07.1" || { echo "expected 25.07.1, got: $ver"; exit 1; }

hx --health > /tmp/hx-health.txt 2>&1 || true
grep -q "rust" /tmp/hx-health.txt || { echo "hx --health did not list rust"; cat /tmp/hx-health.txt; exit 1; }

grep -q 'theme = "nord"' "$HOME/.config/helix/config.toml" || {
    echo "shared config missing Nord theme"
    ls -la "$HOME/.config/helix" || true
    exit 1
}
echo "ok"
