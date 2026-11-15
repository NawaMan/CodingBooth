#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual test: `booth prepare ubuntu` on real Ubuntu 26.04 machines (docs/REUSE_BOOTH.md)
#
# This test runs experiments/host-provision/ec2-test.sh: one fresh EC2 instance
# per example (default go-example and zig-example, in parallel), `booth prepare
# ubuntu` as the AMI's sudo user, then the example's own in-booth tests in a new
# login. About 5 minutes and a few cents; go-full-example (the xfce variant) adds
# about 12, see docs/REUSE_BOOTH.md.
#
# Every instance, key pair and security group it makes is removed at the end,
# on failure and on Ctrl-C; each instance also terminates itself after 90
# minutes in case this machine dies mid-run. The test fails if anything of its
# run is left. `experiments/host-provision/ec2-test.sh --sweep` removes
# everything the test ever tagged.
#
# Needs: the aws CLI with working credentials (region from its config), ssh,
#        curl, and bin/codingbooth-linux-amd64 from ./build/cli-build.sh.
#        Without aws credentials the test is skipped.
# Env:   CB_EC2_EXAMPLES="a-example b-example"   other examples
#        CB_EC2_TYPE, CB_EC2_DISK_GB, CB_EC2_TTL_MIN, CB_EC2_KEEP: see ec2-test.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v aws >/dev/null || ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "  ⏭️  SKIP: no aws CLI with working credentials"
  exit 0
fi

BIN=bin/codingbooth-linux-amd64
[[ -x "$BIN" ]] || { echo "  ❌ FAIL: $BIN is missing: run ./build/cli-build.sh"; exit 1; }
newer="$(find cli/src experiments/host-provision variants/base -type f -newer "$BIN" \
           -not -path '*/.out/*' -not -name '*-test.sh' -not -name 'check-*.sh' \
           -print -quit 2>/dev/null)"   # the harness scripts run from the checkout, not the kit
[[ -z "$newer" ]] || echo "  ⚠️  $newer is newer than $BIN: the run tests the binary as built (./build/cli-build.sh)"

read -ra examples <<< "${CB_EC2_EXAMPLES:-go-example zig-example}"
if experiments/host-provision/ec2-test.sh "${examples[@]}"; then
  echo "  ✅ PASS: booth prepare ubuntu on EC2: ${examples[*]}"
else
  echo "  ❌ FAIL: booth prepare ubuntu on EC2 (logs: experiments/host-provision/.out/ec2-<example>/)"
  exit 1
fi
