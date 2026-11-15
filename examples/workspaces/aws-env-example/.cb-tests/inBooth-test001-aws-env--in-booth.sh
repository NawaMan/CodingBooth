#!/bin/bash
# The booth authenticates to AWS from the AWS_* variables alone:
# no ~/.aws files are present, `aws configure list` reports the keys and the
# region as coming from the environment, and a real STS call succeeds.
set -euo pipefail

fail() { echo "FAIL: $*"; exit 1; }

echo "=== No ~/.aws credential files in the booth ==="
[[ ! -e "$HOME/.aws/credentials" ]] || fail "~/.aws/credentials exists; this booth must use env vars only"
[[ ! -e "$HOME/.aws/config"      ]] || fail "~/.aws/config exists; this booth must use env vars only"
echo "ok"

echo "=== Keys and region come from the environment ==="
list="$(aws configure list)"
echo "$list"
echo "$list" | grep -E '^\s*access_key\s*:.*:\s*env\s*:' >/dev/null || fail "access_key is not from env"
echo "$list" | grep -E '^\s*secret_key\s*:.*:\s*env\s*:' >/dev/null || fail "secret_key is not from env"
echo "$list" | grep -E '^\s*region\s*:.*:\s*env\s*:'     >/dev/null || fail "region is not from env"

echo "=== STS answers with the caller's identity ==="
arn="$(aws sts get-caller-identity --query Arn --output text)" || fail "aws sts get-caller-identity failed"
[[ "$arn" == arn:aws:* ]] || fail "unexpected ARN: $arn"
echo "ok: authenticated"

echo "=== just check ==="
just check
