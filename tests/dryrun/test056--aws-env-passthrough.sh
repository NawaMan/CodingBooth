#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: aws-env-example's run-args hand the AWS credentials over by name only.
#
# The example's config (aws-cli+env~credential, plus claude-code) lists AWS_* as bare `-e NAME`.
# With the host's variables set, the docker command copies each one by name, so
# the secret values never appear in the command line, the dryrun output or a log.
# A variable the host has not set (here AWS_SESSION_TOKEN, AWS_DEFAULT_REGION)
# is dropped rather than passed empty, and no ~/.aws file is mounted.
# Uses the committed config, so a regenerated example is checked too.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../../examples/workspaces/aws-env-example/.booth/config.toml"

SECRET_ID="AKIACBTESTDRYRUN$$"
SECRET_KEY="cb-test-secret-value-$$"
export AWS_ACCESS_KEY_ID="$SECRET_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_REGION="us-west-2"
unset AWS_SESSION_TOKEN AWS_DEFAULT_REGION AWS_PROFILE

ACTUAL=$(run_coding_booth --config "$CONFIG" --dryrun -- echo test 2>&1 | strip_ansi)

FAILED=0
check() { # check <n> <description> <command...>
  local n="$1" desc="$2"
  shift 2
  if "$@"; then
    print_test_result "true" "$0" "$n" "$desc"
  else
    print_test_result "false" "$0" "$n" "$desc"
    FAILED=$((FAILED + 1))
  fi
}
has()     { grep -qF -- "$1" <<<"$ACTUAL"; }
has_not() { ! grep -qF -- "$1" <<<"$ACTUAL"; }

check 1 "AWS_ACCESS_KEY_ID is passed by name"       has "-e AWS_ACCESS_KEY_ID"
check 2 "AWS_SECRET_ACCESS_KEY is passed by name"   has "-e AWS_SECRET_ACCESS_KEY"
check 3 "AWS_REGION is passed by name"              has "-e AWS_REGION"
check 4 "the access key value is never printed"     has_not "$SECRET_ID"
check 5 "the secret key value is never printed"     has_not "$SECRET_KEY"
check 6 "unset AWS_SESSION_TOKEN is dropped"        has_not "AWS_SESSION_TOKEN"
check 7 "unset AWS_DEFAULT_REGION is dropped"       has_not "AWS_DEFAULT_REGION"
check 8 "no ~/.aws file is mounted"                 has_not ".aws/"

exit $FAILED
