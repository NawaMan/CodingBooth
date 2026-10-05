#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

cd /home/coder/code

echo "=== Xonsh version, script, login shell ==="
ver="$(xonsh --version 2>&1 || true)"
echo "$ver" | grep -q "0.24.2" || { echo "expected 0.24.2, got: $ver"; exit 1; }

out="$(xonsh hello.xsh)"
echo "$out"
echo "$out" | grep -q "hello from xonsh" || { echo "script did not greet"; exit 1; }
echo "$out" | grep -q "answer=42" || { echo "script did not print answer=42"; exit 1; }

shell="$(getent passwd coder | cut -d: -f7)"
echo "login shell: $shell"
[[ "$shell" == "/usr/local/bin/xonsh" ]] || { echo "expected USER_SHELL xonsh, got: $shell"; exit 1; }
echo "ok"
