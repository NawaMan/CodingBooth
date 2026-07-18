#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: `booth build` expands variant aliases, as the run path does.
#
# The variant names the base image tag, and only the canonical names are published: an
# unexpanded alias asks docker for `nawaman/codingbooth:xfce-<version>` and the build dies
# on the FROM line. test011-variant.sh covers the same expansion on the run path.

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1
EOF

# Each entry is WANT_VARIANT:GOT_VARIANT
VARIANTS=(
  "desktop-xfce:desktop-xfce"

  # aliases
  "default:base"
  "console:base"
  "ide:codeserver"
  "desktop:desktop-xfce"
  "xfce:desktop-xfce"
  "kde:desktop-kde"
  "lxqt:desktop-lxqt"
  "wayland:desktop-wayland"
)

ALL_PASSED=true
test_num=0

for entry in "${VARIANTS[@]}"; do
    test_num=$((test_num + 1))
    WANT_VARIANT="${entry%%:*}"
    GOT_VARIANT="${entry#*:}"

    ACTUAL=$(run_coding_booth build --dryrun --code "$TEST_DIR" --variant "${WANT_VARIANT}" 2>/dev/null)
    EXPECT="--build-arg 'BOOTH_VARIANT_TAG=${GOT_VARIANT}'"

    # `--` : the pattern starts with "--", which grep would otherwise read as a flag.
    if echo "$ACTUAL" | grep -qF -- "$EXPECT"; then
        print_test_result "true" "$0" "$(printf '%03d' "$test_num")" \
            "build --variant ${WANT_VARIANT} builds FROM ${GOT_VARIANT}"
    else
        print_test_result "false" "$0" "$(printf '%03d' "$test_num")" \
            "build --variant ${WANT_VARIANT} builds FROM ${GOT_VARIANT}"
        echo "Actual output:"
        echo "$ACTUAL"
        ALL_PASSED=false
    fi
done

# An unknown variant is refused rather than passed through to docker as a bogus tag.
test_num=$((test_num + 1))
if run_coding_booth build --dryrun --code "$TEST_DIR" --variant nonesuch > /dev/null 2>&1; then
    print_test_result "false" "$0" "$(printf '%03d' "$test_num")" "build rejects an unknown variant"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "$(printf '%03d' "$test_num")" "build rejects an unknown variant"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
