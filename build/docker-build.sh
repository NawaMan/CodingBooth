#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# docker-build.sh - Build and publish CodingBooth Docker images
#
# This script builds Docker images for all CodingBooth variants (base, notebook,
# codeserver, desktop-xfce, desktop-kde, desktop-lxqt) using multi-architecture support.
# It can build locally or push to Docker Hub with cosign signature verification.
# Run with --help for usage information.
#
set -euo pipefail

# Change to project root (one level up from build/)
cd "$(dirname "$0")/.." || exit 1

# Validate we're in the project root
if [[ ! -f "version.txt" ]] || [[ ! -d "variants" ]]; then
    echo "❌ Error: This script must be run from the project root directory."
    echo "   Usage: ./build/docker-build.sh [options]"
    exit 1
fi

#== ENVIRONMENTAL VARIABLES ==

# Cosign key configuration
COSIGN_KEY_FILE_DEFAULT="${HOME}/.config/nawaman-codingbooth/cosign.key"
COSIGN_KEY_FILE="${COSIGN_KEY_FILE:-$COSIGN_KEY_FILE_DEFAULT}"
COSIGN_KEY_REF=""

# --- Settings ---
IMAGE_NAME="nawaman/codingbooth"
PLATFORMS="linux/amd64,linux/arm64"
VERSION_FILE="version.txt"

# All known variants
ALL_VARIANTS=(
  base
  notebook
  codeserver
  desktop-xfce
  desktop-kde
  desktop-lxqt
  desktop-wayland
)

# Script state (globals)
PUSH="false"
NO_CACHE="false"
SKIP_LOGIN="false"
VARIANTS_TO_BUILD=()

# Native multi-arch support.
#   ARCH set   -> build that single architecture natively and push by digest
#                 (no tags, no signing — the merge step assembles & signs).
#   MERGE=true -> assemble previously-pushed per-arch digests into the
#                 multi-arch tags, then cosign-sign them.
# When both are empty/false the legacy single-runner path is used, which builds
# all PLATFORMS at once (emulating the non-native arch under QEMU).
ARCH=""
MERGE="false"
DIGEST_DIR="build/.digests"
VALID_ARCHES=(amd64 arm64)

# ======================
#         Main
# ======================
Main() {
  ParseArgs "$@"
  ValidateVariants
  ValidateArch
  SetupPushEnvironment
  echo

  # Get the version once, reuse for all variants
  local version
  version="$(resolve_version)"

  # Merge mode: assemble per-arch digests into multi-arch tags, then sign.
  if [[ "${MERGE}" == "true" ]]; then
    Log "=== Merge Phase ==="
    echo
    for v in "${VARIANTS_TO_BUILD[@]}"; do
      MergeVariant "$v" "${version}"
    done
    return 0
  fi

  Log "=== Build Phase ==="
  echo

  # Stage docs if building base variant
  local needs_staging=false
  for v in "${VARIANTS_TO_BUILD[@]}"; do
    if [[ "$v" == "base" ]]; then
      needs_staging=true
      break
    fi
  done

  if [[ "$needs_staging" == "true" ]]; then
    StageDocsForBase
  fi

  # Ensure cleanup happens even on error
  trap 'CleanupStaging' EXIT

  for v in "${VARIANTS_TO_BUILD[@]}"; do
    BuildVariant "$v" "${version}" "${PUSH}" "${NO_CACHE}"
  done

  # Cleanup staging (also called by trap, but explicit is clearer)
  CleanupStaging
  trap - EXIT
}


# ======================
#       Functions
# (determine/return; snake_case; with `function`)
# ======================

function is_valid_variant() {
  local v="$1"
  local known
  for known in "${ALL_VARIANTS[@]}"; do
    if [[ "$known" == "$v" ]]; then
      return 0
    fi
  done
  return 1
}

function resolve_version() {
  local tag=""
  if [[ -f "${VERSION_FILE}" ]]; then
    tag="$(tr -d ' \t\n\r' < "${VERSION_FILE}")"
    [[ -z "${tag}" ]] && Die "Version file '${VERSION_FILE}' is empty."
  else
    Die "No --version provided and '${VERSION_FILE}' not found."
  fi

  echo "${tag}"
}

function select_cosign_key() {
  if [[ -n "${COSIGN_KEY:-}" ]]; then
    echo "env://COSIGN_KEY"
  else
    local key_file="${COSIGN_KEY_FILE:-$COSIGN_KEY_FILE_DEFAULT}"

    if [[ ! -f "$key_file" ]]; then
      Die "Cosign key file not found at '$key_file'. Set COSIGN_KEY or COSIGN_KEY_FILE."
    fi

    echo "$key_file"
  fi
}

# Extract the pushed image digest from a `docker buildx build --metadata-file`.
# Prefers jq; falls back to a grep/sed scan so the script works without jq.
function extract_digest() {
  local meta="$1"
  local d=""
  if command -v jq >/dev/null 2>&1; then
    d="$(jq -r '."containerimage.digest" // empty' "$meta" 2>/dev/null || true)"
  fi
  if [[ -z "$d" ]]; then
    d="$(grep -o '"containerimage.digest"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta" 2>/dev/null \
          | sed -E 's/.*"(sha256:[a-f0-9]+)".*/\1/' | head -n1 || true)"
  fi
  echo "$d"
}

# ======================
#        Actions
# (side effects; no `function` keyword)
# ======================

Log() { printf "\033[1;34m[info]\033[0m %s\n" "$1"; }
Err() { printf "\033[1;31m[err]\033[0m %s\n" "$1" >&2; }
Die() { Err "$1"; exit 1; }

# Stage documentation files for base variant build
# These files are outside the base context, so we copy them to a staging directory
StageDocsForBase() {
  local stage_dir="variants/base/_stage"

  Log "Staging documentation files for base variant..."

  # Clean and create staging directory
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir/variants"

  # Copy documentation files
  cp README.md "$stage_dir/"
  cp LICENSE "$stage_dir/"
  cp version.txt "$stage_dir/"
  cp docs/AGENT.md "$stage_dir/"

  # Copy docs markdown files (excluding images to keep image small)
  mkdir -p "$stage_dir/docs"
  find docs -name '*.md' | while read -r f; do
    mkdir -p "$stage_dir/$(dirname "$f")"
    cp "$f" "$stage_dir/$f"
  done

  # Copy all variant Dockerfiles
  for v in "${ALL_VARIANTS[@]}"; do
    mkdir -p "$stage_dir/variants/$v"
    cp "variants/$v/Dockerfile" "$stage_dir/variants/$v/"
  done

  Log "Staged files to $stage_dir"
}

# Clean up staging directory after build
CleanupStaging() {
  local stage_dir="variants/base/_stage"
  if [[ -d "$stage_dir" ]]; then
    Log "Cleaning up staging directory..."
    rm -rf "$stage_dir"
  fi
}

BuildVariant() {
  local variant="$1"
  local version="$2"
  local do_push="$3"
  local no_cache="$4"

  local tags_arg=()
  local context_dir="variants/${variant}"
  local docker_file="${context_dir}/Dockerfile"

  tags_arg+=( -t "${IMAGE_NAME}:${variant}-${version}" )

  if [[ ! "$version" =~ --rc([0-9]+)?$ ]]; then
    tags_arg+=( -t "${IMAGE_NAME}:${variant}-latest" )
  fi

  # Pretty-print tags
  local tags_str=""
  printf -v tags_str '%s ' "${tags_arg[@]}"
  tags_str="${tags_str//-t /}"

  Log "[$variant]: Image:      ${IMAGE_NAME}"
  Log "[$variant]: Variant:    ${variant}"
  Log "[$variant]: Version:    ${version}"
  Log "[$variant]: Context:    ${context_dir}"
  Log "[$variant]: Dockerfile: ${docker_file}"
  Log "[$variant]: Tags:       ${tags_str}"
  Log "[$variant]: No cache:   ${no_cache}"
  echo ""

  # --- Sanity checks ---
  [[ -d "${context_dir}" ]] || Die "Context dir not found: ${context_dir}"
  [[ -f "${docker_file}" ]] || Die "Dockerfile not found: ${docker_file}"

  # Optional args
  local no_cache_arg=()
  if [[ "${no_cache}" == "true" ]]; then
    no_cache_arg+=( --no-cache )
  fi

  if [[ "${do_push}" == "true" ]]; then
    Log "[$variant]: Setting up buildx (driver: docker-container)"
    docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
    docker buildx inspect --bootstrap >/dev/null

    if [[ -n "${ARCH}" ]]; then
      # --- Native per-arch build: push by digest only (no tags, no signing). ---
      # The merge step (--merge) assembles all per-arch digests into the
      # multi-arch tags and signs them.
      local platform="linux/${ARCH}"
      local meta_file
      meta_file="$(mktemp)"

      Log "[$variant]: Building ${platform} natively (push by digest)"
      docker buildx build \
        "${no_cache_arg[@]}" \
        --platform "${platform}" \
        -f "${docker_file}" \
        --build-arg "BOOTH_VERSION_TAG=${version}" \
        --build-arg "FINAL_STAGE=base" \
        --output "type=image,name=${IMAGE_NAME},push-by-digest=true,push=true" \
        --metadata-file "${meta_file}" \
        "${context_dir}" \
        --progress=auto

      local digest
      digest="$(extract_digest "${meta_file}")"
      rm -f "${meta_file}"
      [[ -n "${digest}" ]] || Die "[$variant]: failed to capture image digest for ${platform}"

      mkdir -p "${DIGEST_DIR}"
      local digest_file="${DIGEST_DIR}/${variant}-${ARCH}.digest"
      echo "${digest}" > "${digest_file}"
      Log "[$variant]: ${platform} pushed by digest: ${digest}"
      Log "[$variant]: Wrote ${digest_file}"
      Log "[$variant]: Done (per-arch). Run with --merge to assemble & sign."
      echo
      return 0
    fi

    # --- Legacy single-runner multi-arch path (non-native arch via QEMU). ---
    Log "[$variant]: ⚠️  Building all of ${PLATFORMS} on one runner; the non-native arch is emulated under QEMU."
    Log "[$variant]: For native builds, use --arch <amd64|arm64> per runner, then --merge."
    Log "[$variant]: Building with buildx (push)"
    docker buildx build \
      "${no_cache_arg[@]}" \
      --platform "${PLATFORMS}" \
      -f "${docker_file}" \
      --build-arg "BOOTH_VERSION_TAG=${version}" \
      --build-arg "FINAL_STAGE=base" \
      "${tags_arg[@]}" \
      "${context_dir}" \
      --push \
      --progress=auto

    if [[ ! "$version" =~ --rc([0-9]+)?$ ]]; then
      Log "[$variant]: Calling cosign to sign pushed images for variant '${variant}'"
      SignImages "${tags_arg[@]}"
    else
      Log "[$variant]: Skipping cosign signing for RC version: ${version}"
    fi

    # Pull back the main tag for local use
    Log "[$variant]: Pulling pushed image for local use"
    docker pull "${IMAGE_NAME}:${variant}-${version}"

  else
    Log "[$variant]: Local build (plain 'docker build')"
    export DOCKER_BUILDKIT=1
    docker build \
      "${no_cache_arg[@]}" \
      -f "${docker_file}" \
      --build-arg "BOOTH_VERSION_TAG=${version}" \
      "${tags_arg[@]}" \
      "${context_dir}" \
      --progress=auto
  fi

  Log "[$variant]: Done."
  echo
}

# Assemble previously-pushed per-arch digests into the multi-arch tags, then sign.
# Reads ${DIGEST_DIR}/${variant}-<arch>.digest files produced by per-arch builds.
MergeVariant() {
  local variant="$1"
  local version="$2"

  local tags_arg=()
  tags_arg+=( -t "${IMAGE_NAME}:${variant}-${version}" )
  if [[ ! "$version" =~ --rc([0-9]+)?$ ]]; then
    tags_arg+=( -t "${IMAGE_NAME}:${variant}-latest" )
  fi

  # Collect the per-arch source references (IMAGE_NAME@sha256:...).
  local sources=()
  local f digest
  shopt -s nullglob
  for f in "${DIGEST_DIR}/${variant}-"*.digest; do
    digest="$(tr -d ' \t\n\r' < "$f")"
    [[ -n "$digest" ]] || continue
    sources+=( "${IMAGE_NAME}@${digest}" )
  done
  shopt -u nullglob

  [[ "${#sources[@]}" -gt 0 ]] || \
    Die "[$variant]: no per-arch digests found in '${DIGEST_DIR}' (expected ${variant}-<arch>.digest). Run the per-arch builds first."

  Log "[$variant]: Merging ${#sources[@]} arch image(s) into multi-arch tags:"
  local s
  for s in "${sources[@]}"; do Log "  - ${s}"; done

  docker buildx imagetools create "${tags_arg[@]}" "${sources[@]}"

  if [[ ! "$version" =~ --rc([0-9]+)?$ ]]; then
    Log "[$variant]: Signing merged manifest tags with cosign"
    SignImages "${tags_arg[@]}"
  else
    Log "[$variant]: Skipping cosign signing for RC version: ${version}"
  fi

  Log "[$variant]: Pulling merged image for local use"
  docker pull "${IMAGE_NAME}:${variant}-${version}"
  Log "[$variant]: Merge done."
  echo
}

ParseArgs() {
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push)        PUSH="true";        shift ;;
      --no-cache)    NO_CACHE="true";    shift ;;
      --skip-login)  SKIP_LOGIN="true";  shift ;;
      --arch)        shift; ARCH="${1:-}"; [[ -n "$ARCH" ]] || Die "--arch requires a value (amd64|arm64)"; shift ;;
      --merge)       MERGE="true";       shift ;;
      -h|--help)     Usage;              exit 0 ;;
      *)             positional+=("$1"); shift ;;
    esac
  done

  if ((${#positional[@]} > 0)); then
    VARIANTS_TO_BUILD=("${positional[@]}")
  else
    VARIANTS_TO_BUILD=("${ALL_VARIANTS[@]}")
  fi
}

SetupPushEnvironment() {
  # Registry access is needed whenever we push (build) or merge.
  local needs_registry="false"
  [[ "${PUSH}" == "true" || "${MERGE}" == "true" ]] && needs_registry="true"

  # Signing happens only where tags are produced: the merge step, or the
  # legacy single-runner multi-arch push. Per-arch builds (ARCH set) push by
  # digest and never sign, so they don't require cosign.
  local needs_cosign="false"
  if [[ "${MERGE}" == "true" ]] || { [[ "${PUSH}" == "true" && -z "${ARCH}" ]]; }; then
    needs_cosign="true"
  fi

  if [[ "${needs_registry}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "❌ Username or password not set."
    echo "   Make sure both DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are set."
    exit 3
  fi

  if [[ "${SKIP_LOGIN}" == "true" ]]; then
    Log "Skipping docker login (already performed by caller)"
  else
    Log "Logging in to Docker Hub as ${DOCKERHUB_USERNAME}"
    if ! echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin; then
      echo "❌ Docker login failed"
      exit 4
    fi
  fi
  echo

  if [[ "${needs_cosign}" == "true" ]]; then
    if ! command -v cosign >/dev/null 2>&1; then
      Die "cosign not found in PATH but signing is required. Install cosign to sign images."
    fi
    COSIGN_KEY_REF="$(select_cosign_key)"
    Log "Cosign: using key reference: ${COSIGN_KEY_REF}"
  fi
}

SignImages() {
  local -a args=("$@")
  local -a tags=()
  local token
  local expect_ref=0

  Log "Extracting image references from -t <ref> pairs"
  for token in "${args[@]}"; do
    if (( expect_ref )); then
      tags+=("$token")
      expect_ref=0
    elif [[ "$token" == "-t" ]]; then
      expect_ref=1
    fi
  done

  if (( expect_ref )); then
    Die "Malformed TAGS_ARG: '-t' at end with no image reference"
  fi

  if [[ "${#tags[@]}" -eq 0 ]]; then
    Log "Cosign: no images found to sign (TAGS_ARG was empty?)"
    return 0
  fi

  Log "Cosign: signing the following tags (cosign will resolve digests):"
  local tag
  for tag in "${tags[@]}"; do
    Log "  - ${tag}"
  done

  for tag in "${tags[@]}"; do
    if [[ "${VERBOSE:-false}" == "true" ]]; then
      Log "Cosign: signing tag ${tag} with key ${COSIGN_KEY_REF}"
      COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
      cosign sign --yes --upload=false --key "${COSIGN_KEY_REF}" "${tag}" || \
        Die "cosign sign failed for image tag: ${tag}"
    else
      Log "Cosign: signing tag ${tag}"

      # Retry to handle registry propagation delays (common right after buildx --push)
      local attempt=1
      local max_attempts=4
      local err_out=""
      while (( attempt <= max_attempts )); do
        err_out="$(
          COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
          cosign sign --yes --upload=false --key "${COSIGN_KEY_REF}" "${tag}" 2>&1 >/dev/null
        )" && break

        if (( attempt == max_attempts )); then
          Err "Cosign: failed to sign ${tag}. cosign output:"
          printf '%s\n' "${err_out}" >&2
          Die "cosign sign failed for image tag: ${tag} (re-run with VERBOSE=true for full logs)"
        fi

        Log "Cosign: sign failed for ${tag} (attempt ${attempt}/${max_attempts}); retrying shortly..."
        sleep $(( attempt * 2 ))
        attempt=$(( attempt + 1 ))
      done
    fi
  done

  Log "Cosign: successfully signed ${#tags[@]} tag(s)."
}

Usage() {
  cat <<EOF
Usage: ./docker-build.sh [--push] [--arch <a>] [--merge] [--no-cache] [--skip-login] [variant ...]
Options:
  --push          Build and push using buildx and sign images with cosign
  --arch <a>      Build a single architecture natively (amd64|arm64) and push by
                  digest, without tags or signing. Requires --push. Run once per
                  runner of that architecture, then assemble with --merge.
  --merge         Assemble per-arch digests (from prior --arch builds) into the
                  multi-arch tags, then sign them. Mutually exclusive with --arch.
  --no-cache      Build without using cache
  --skip-login    Skip 'docker login' (assume caller already logged in).
  -h, --help      Show this help

Without --arch/--merge, --push builds all of '${PLATFORMS}' on one runner,
emulating the non-native architecture under QEMU (kept for local/standalone use).

Variants (if none provided, all are built):
  base
  notebook
  codeserver
  desktop-xfce
  desktop-kde
  desktop-lxqt
  desktop-wayland

Environment:
  COSIGN_KEY        Cosign private key content (PEM) stored directly in env; used if set
  COSIGN_KEY_FILE   Path to cosign private key file (default: ${COSIGN_KEY_FILE_DEFAULT})
  COSIGN_PASSWORD   Password for the private key (if the key is encrypted)

Examples:
  ./build/docker-build.sh                   # local build of all variants
  ./build/docker-build.sh base              # build only 'base'
  ./build/docker-build.sh --push base       # legacy multi-arch push + sign (QEMU)

  # Native multi-arch (one build per arch, then merge):
  ./build/docker-build.sh --push --arch amd64 base   # on an amd64 runner
  ./build/docker-build.sh --push --arch arm64 base   # on an arm64 runner
  ./build/docker-build.sh --merge base               # assemble + sign the tags
EOF
}

ValidateVariants() {
  local v
  for v in "${VARIANTS_TO_BUILD[@]}"; do
    if ! is_valid_variant "$v"; then
      Err "Unknown variant: '$v'"
      echo
      Usage
      exit 2
    fi
  done
}

ValidateArch() {
  if [[ "${MERGE}" == "true" && -n "${ARCH}" ]]; then
    Die "--arch and --merge are mutually exclusive."
  fi

  [[ -z "${ARCH}" ]] && return 0

  local known found="false"
  for known in "${VALID_ARCHES[@]}"; do
    [[ "${known}" == "${ARCH}" ]] && found="true"
  done
  [[ "${found}" == "true" ]] || Die "Invalid --arch '${ARCH}'. Supported: ${VALID_ARCHES[*]}."

  if [[ "${PUSH}" != "true" ]]; then
    Die "--arch requires --push (per-arch builds push by digest)."
  fi
}

# --- Entry point ---
Main "$@"
