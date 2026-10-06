#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

cd /home/coder/code

echo "=== bash-3.2 version, count-args, empty-array rejection ==="
ver="$(bash-3.2 --version | head -1)"
echo "$ver"
echo "$ver" | grep -q "3.2.57" || { echo "expected 3.2.57, got: $ver"; exit 1; }

sys="$(bash --version | head -1)"
echo "login bash: $sys"
echo "$sys" | grep -q "3.2.57" && { echo "/bin/bash should stay the distro bash"; exit 1; }

zero="$(./scripts/count-args.sh)"
echo "$zero"
[[ "$zero" == "count=0" ]] || { echo "expected count=0, got: $zero"; exit 1; }

two="$(./scripts/count-args.sh one two)"
echo "$two"
[[ "$two" == "count=2" ]] || { echo "expected count=2, got: $two"; exit 1; }

cat > /tmp/bash-unsafe.sh <<'EOF'
set -u
a=()
echo "${a[@]}"
echo survived
EOF
if bash-3.2 /tmp/bash-unsafe.sh > /tmp/bash-unsafe.out 2> /tmp/bash-unsafe.err; then
    echo "empty array under set -u should fail on bash 3.2"
    exit 1
fi
if grep -q survived /tmp/bash-unsafe.out; then
    echo "unsafe script should exit before printing survived"
    exit 1
fi
grep -q "unbound variable" /tmp/bash-unsafe.err
echo "ok"
