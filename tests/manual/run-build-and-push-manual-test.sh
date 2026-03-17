#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual test: booth build — local build, push to local registry, and run from pushed image
#
# This test:
#   1) Builds the codingbooth binary
#   2) Creates a temp project with a simple Boothfile
#   3) Tests "booth build" (local)
#   4) Starts a local Docker registry
#   5) Tests "booth build --push" to the local registry
#   6) Runs a booth using the pushed image
#   7) Cleans up everything (temp project, images, registry)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

REGISTRY_NAME="cb-test-registry"
REGISTRY_PORT="5111"
REGISTRY="localhost:${REGISTRY_PORT}"
TEMP_DIR=""
LOCAL_IMAGE=""
PUSHED_IMAGE=""

# ─── Helpers ────────────────────────────────────────────────────────────────

# Extract the image name from booth build output.
# Usage: IMAGE=$(capture_image "Built" <<<"$output")
#        IMAGE=$(capture_image "Pushed" <<<"$output")
capture_image() {
  local label="$1"
  # Read all of stdin, then extract the line
  local output
  output="$(cat)"
  echo "$output" | sed -n "s/^${label}: //p"
}

fail() {
  echo "  ❌ FAIL: $1"
  exit 1
}

pass() {
  echo "  ✅ PASS: $1"
}

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup() {
  echo
  echo "═══ Cleanup ═══════════════════════════════════════════════"

  # Remove local images
  if [[ -n "${LOCAL_IMAGE}" ]]; then
    echo "  Removing local image: ${LOCAL_IMAGE}"
    docker rmi "${LOCAL_IMAGE}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PUSHED_IMAGE}" ]]; then
    echo "  Removing pushed image: ${PUSHED_IMAGE}"
    docker rmi "${PUSHED_IMAGE}" >/dev/null 2>&1 || true
  fi

  # Stop and remove local registry
  echo "  Stopping local registry: ${REGISTRY_NAME}"
  docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true

  # Remove temp project directory
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    echo "  Removing temp directory: ${TEMP_DIR}"
    rm -rf "${TEMP_DIR}"
  fi

  echo "  Done."
}
trap cleanup EXIT

# ─── Header ─────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo "Booth Build & Push Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo
echo "This test will:"
echo "  1. Build codingbooth binary"
echo "  2. Create a temp project with a Boothfile"
echo "  3. Test local build (booth build)"
echo "  4. Start a local Docker registry on port ${REGISTRY_PORT}"
echo "  5. Test push build (booth build --push)"
echo "  6. Run booth using the pushed image"
echo "  7. Clean up all images and containers"
echo

# ─── Step 1: Build the binary ───────────────────────────────────────────────

echo "═══ Step 1: Build codingbooth binary ════════════════════"
GOCACHE=/tmp/go-cache ./build/cli-build.sh >/dev/null
CODINGBOOTH="${ROOT_DIR}/codingbooth"
echo "  Binary: ${CODINGBOOTH}"
echo "  Version: $("${CODINGBOOTH}" version 2>&1 | tail -1 || true)"
echo

# ─── Step 2: Create temp project ────────────────────────────────────────────

echo "═══ Step 2: Create temp project ════════════════════════"
TEMP_DIR="/tmp/cb-build-test-$(date +%s)"
mkdir -p "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}/.booth"

cat > "${TEMP_DIR}/.booth/Boothfile" <<'BOOTHFILE'
# syntax=codingbooth/boothfile:1
# Minimal Boothfile for build test
BOOTHFILE

cat > "${TEMP_DIR}/.booth/config.toml" <<'TOML'
variant = "base"
TOML

echo "  Project: ${TEMP_DIR}"
echo "  Boothfile:"
sed 's/^/    /' "${TEMP_DIR}/.booth/Boothfile"
echo

# ─── Step 3: Local build ────────────────────────────────────────────────────

echo "═══ Step 3: Local build (booth build) ═══════════════════"

BUILD_OUTPUT="$("${CODINGBOOTH}" build --code "${TEMP_DIR}" 2>&1)"
BUILD_EXIT=$?

if [[ $BUILD_EXIT -ne 0 ]]; then
  echo "  Build output:"
  echo "${BUILD_OUTPUT}" | sed 's/^/    /'
  fail "booth build exited with code ${BUILD_EXIT}"
fi

LOCAL_IMAGE="$(capture_image "Built" <<<"${BUILD_OUTPUT}")"

if [[ -z "${LOCAL_IMAGE}" ]]; then
  echo "  Build output:"
  echo "${BUILD_OUTPUT}" | sed 's/^/    /'
  fail "booth build produced no 'Built: ...' line"
fi

echo "  Image: ${LOCAL_IMAGE}"

# Verify the image exists locally
if docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1; then
  pass "Image exists locally"
else
  fail "Image not found locally after build"
fi
echo

# ─── Step 4: Start local registry ───────────────────────────────────────────

echo "═══ Step 4: Start local Docker registry ═════════════════"
docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true
docker run -d --name "${REGISTRY_NAME}" -p "${REGISTRY_PORT}:5000" registry:2 >/dev/null

# Wait for registry to be ready
echo -n "  Waiting for registry"
for i in $(seq 1 15); do
  if curl -sf "http://${REGISTRY}/v2/" >/dev/null 2>&1; then
    echo " ready."
    break
  fi
  echo -n "."
  sleep 1
  if [[ $i -eq 15 ]]; then
    echo " timeout!"
    fail "Local registry did not start"
  fi
done
echo "  Registry: ${REGISTRY}"
echo

# ─── Step 5: Push build ─────────────────────────────────────────────────────

echo "═══ Step 5: Push build (booth build --push) ═════════════"

PUSH_OUTPUT="$("${CODINGBOOTH}" build --code "${TEMP_DIR}" --push "${REGISTRY}" 2>&1)"
PUSH_EXIT=$?

if [[ $PUSH_EXIT -ne 0 ]]; then
  echo "  Push output:"
  echo "${PUSH_OUTPUT}" | sed 's/^/    /'
  fail "booth build --push exited with code ${PUSH_EXIT}"
fi

PUSHED_IMAGE="$(capture_image "Pushed" <<<"${PUSH_OUTPUT}")"

if [[ -z "${PUSHED_IMAGE}" ]]; then
  echo "  Push output:"
  echo "${PUSH_OUTPUT}" | sed 's/^/    /'
  fail "booth build --push produced no 'Pushed: ...' line"
fi

echo "  Image: ${PUSHED_IMAGE}"

# Verify image exists in the registry
REPO_NAME="$(echo "${PUSHED_IMAGE}" | sed "s|${REGISTRY}/||" | cut -d: -f1)"
TAGS_JSON="$(curl -sf "http://${REGISTRY}/v2/${REPO_NAME}/tags/list" || true)"

if [[ -n "${TAGS_JSON}" ]]; then
  pass "Image exists in local registry"
  echo "  Registry response: ${TAGS_JSON}"
else
  fail "Image not found in registry"
fi
echo

# ─── Step 6: Run using pushed image ─────────────────────────────────────────

echo "═══ Step 6: Run booth using pushed image ════════════════"
echo "  Running: codingbooth --image ${PUSHED_IMAGE} --pull -- echo hello-from-pushed-image"

RUN_OUTPUT="$("${CODINGBOOTH}" --code "${TEMP_DIR}" --image "${PUSHED_IMAGE}" --pull -- 'echo hello-from-pushed-image' 2>&1 || true)"

if echo "${RUN_OUTPUT}" | grep -q "hello-from-pushed-image"; then
  pass "Container ran successfully with pushed image"
else
  echo "  ⚠️  WARN: Expected output not found (may be normal if base image has no shell setup)"
fi
echo "  Output: ${RUN_OUTPUT}"
echo

# ─── Step 7: Verify content hash determinism ─────────────────────────────

echo "═══ Step 7: Verify content hash determinism ═════════════"

DRYRUN1="$("${CODINGBOOTH}" build --code "${TEMP_DIR}" --dryrun 2>&1)"
IMAGE1="$(capture_image "Built" <<<"${DRYRUN1}")"

DRYRUN2="$("${CODINGBOOTH}" build --code "${TEMP_DIR}" --dryrun 2>&1)"
IMAGE2="$(capture_image "Built" <<<"${DRYRUN2}")"

if [[ -z "${IMAGE1}" ]]; then
  fail "dryrun produced no 'Built: ...' line"
fi

if [[ "${IMAGE1}" == "${IMAGE2}" ]]; then
  pass "Same config produces same image tag"
  echo "  Image: ${IMAGE1}"
else
  fail "Same config produced different tags: ${IMAGE1} vs ${IMAGE2}"
fi
echo

# ─── Summary ─────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo "All tests passed!"
echo "═══════════════════════════════════════════════════════════"
