#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual test: `booth prepare` on real GitHub Actions runners (docs/REUSE_BOOTH.md)
#
# This test:
#   1) Runs the local refusals lane (experiments/host-provision/prepare-test.sh
#      refusals): seconds, in a throwaway ubuntu:26.04 container
#   2) Starts the hand-started workflow .github/workflows/host-provision-exp.yaml
#      on this branch: `booth prepare gha` on ~90 examples, then each example's
#      own in-booth tests in a later step (about 25 minutes)
#   3) Waits for it and prints one line per failed example; exits 1 on any failure
#
# The workflow runs the code on GitHub, so the branch must already be pushed and
# origin must have this exact HEAD. The test never pushes: it stops and says so.
#
# Needs: docker, gh (logged in, allowed to run workflows on the repo).
# Env:   CB_GHA_REF=<branch>  run another pushed branch instead of the current one
#        CB_GHA_SKIP_LOCAL=1  skip step 1

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

WORKFLOW="host-provision-exp.yaml"

fail() { echo "  ❌ FAIL: $1"; exit 1; }
pass() { echo "  ✅ PASS: $1"; }

command -v gh >/dev/null     || fail "gh is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in (run: gh auth login)"

# ─── 1) Local refusals lane ─────────────────────────────────────────────────

if [[ "${CB_GHA_SKIP_LOCAL:-}" != "1" ]]; then
  echo "═══ 1) Local lane: prepare-test.sh refusals ═══════════════════════"
  command -v docker >/dev/null || fail "docker is not installed"
  ./build/cli-build.sh >/dev/null
  if experiments/host-provision/prepare-test.sh refusals; then
    pass "refusals"
  else
    fail "prepare-test.sh refusals (see experiments/host-provision/.out/)"
  fi
fi

# ─── 2) Start the workflow on a pushed ref ─────────────────────────────────

echo
echo "═══ 2) GHA: $WORKFLOW ═══════════════════════════════════════"
REF="${CB_GHA_REF:-$(git branch --show-current)}"
[[ -n "$REF" ]] || fail "detached HEAD: set CB_GHA_REF=<branch>"

git fetch -q origin "$REF" 2>/dev/null || fail "origin has no branch '$REF': push it first (git push -u origin $REF)"
REMOTE_SHA="$(git rev-parse "origin/$REF")"
if [[ -z "${CB_GHA_REF:-}" ]]; then
  LOCAL_SHA="$(git rev-parse HEAD)"
  [[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] \
    || fail "origin/$REF is ${REMOTE_SHA:0:8} but HEAD is ${LOCAL_SHA:0:8}: push (or pull) first, the run tests what origin has"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
    || echo "  ⚠️  uncommitted changes are not part of the run"
fi
echo "  ref $REF @ ${REMOTE_SHA:0:8}"

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run "$WORKFLOW" --ref "$REF" >/dev/null || fail "gh workflow run $WORKFLOW --ref $REF"

# `gh workflow run` prints no run id: find the run this call made.
RUN_ID=""
for _ in $(seq 1 30); do
  RUN_ID="$(gh run list --workflow "$WORKFLOW" --branch "$REF" --event workflow_dispatch -L 10 \
              --json databaseId,headSha,createdAt \
              --jq "[.[] | select(.headSha == \"$REMOTE_SHA\" and .createdAt >= \"$STARTED\")] | last | .databaseId // empty")"
  [[ -n "$RUN_ID" ]] && break
  sleep 4
done
[[ -n "$RUN_ID" ]] || fail "started the workflow but could not find its run"
URL="$(gh run view "$RUN_ID" --json url --jq .url)"
echo "  run $RUN_ID: $URL"

# ─── 3) Wait, then report ───────────────────────────────────────────────────

echo
echo "═══ 3) Waiting for the run (about 25 minutes) ═══════════════════"
gh run watch "$RUN_ID" --interval 60 >/dev/null 2>&1 || true

SUMMARY="$(gh run view "$RUN_ID" --json conclusion,jobs --jq '
  .conclusion,
  ([.jobs[].conclusion] | group_by(.) | map("\(.[0]): \(length)") | join(", "))')"
CONCLUSION="$(sed -n 1p <<<"$SUMMARY")"
echo "  jobs: $(sed -n 2p <<<"$SUMMARY")"

if [[ "$CONCLUSION" == "success" ]]; then
  pass "every job of run $RUN_ID"
  exit 0
fi

echo "  Failed jobs (step that failed):"
gh run view "$RUN_ID" --json jobs --jq '
  .jobs[] | select(.conclusion != "success" and .conclusion != "skipped")
  | "    - \(.name): \([.steps[] | select(.conclusion == "failure") | .name] | join(", "))"'
echo "  Details: gh run view $RUN_ID --log-failed   ($URL)"
fail "run $RUN_ID concluded '$CONCLUSION'"
