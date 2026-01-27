#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# docker-build.sh - Build and publish CodingBooth Docker images
#
# This script builds Docker images for all CodingBooth variants (base, notebook,
# codeserver, desktop-xfce, desktop-kde) using multi-architecture support.
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
COSIGN_KEY_FILE_DEFAULT="${HOME}/.config/nawaman-coding-booth/cosign.key"
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
)

# Script state (globals)
PUSH="false"
NO_CACHE="false"
VARIANTS_TO_BUILD=()

# ======================
#         Main
# ======================
Main() {
  ParseArgs "$@"
  ValidateVariants
  SetupPushEnvironment
  echo

  Log "=== Build ==="
  echo

  # Get the version once, reuse for all variants
  local version
  version="$(resolve_version)"

  Log "=== Build Phase ==="

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
    Log "[$variant]: Setting up buildx (driver: docker-container; multi-arch: ${PLATFORMS})"
    docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
    docker buildx inspect --bootstrap >/dev/null

    Log "[$variant]: Building with buildx (push)"
    docker buildx build \
      "${no_cache_arg[@]}" \
      --platform "${PLATFORMS}" \
      -f "${docker_file}" \
      --build-arg "CB_VERSION_TAG=${version}" \
      --build-arg "FINAL_STAGE=base" \
      "${tags_arg[@]}" \
      "${context_dir}" \
      --push

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
      --build-arg "CB_VERSION_TAG=${version}" \
      "${tags_arg[@]}" \
      "${context_dir}"
  fi

  Log "[$variant]: Done."
  echo
}

ParseArgs() {
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push)       PUSH="true";      shift ;;
      --no-cache)   NO_CACHE="true";  shift ;;
      -h|--help)    Usage;            exit 0 ;;
      *)            positional+=("$1"); shift ;;
    esac
  done

  if ((${#positional[@]} > 0)); then
    VARIANTS_TO_BUILD=("${positional[@]}")
  else
    VARIANTS_TO_BUILD=("${ALL_VARIANTS[@]}")
  fi
}

SetupPushEnvironment() {
  if [[ "${PUSH}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "❌ Username or password not set."
    echo "   Make sure both DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are set."
    exit 3
  fi

  Log "Logging in to Docker Hub as ${DOCKERHUB_USERNAME}"
  if ! echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin; then
    echo "❌ Docker login failed"
    exit 4
  fi
  echo

  if ! command -v cosign >/dev/null 2>&1; then
    Die "cosign not found in PATH but --push was requested. Install cosign to sign images."
  fi

  COSIGN_KEY_REF="$(select_cosign_key)"
  Log "Cosign: using key reference: ${COSIGN_KEY_REF}"
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
Usage: ./docker-build.sh [--push] [--no-cache] [variant ...]
Options:
  --push          Build and push using buildx (multi-arch) and sign images with cosign
  --no-cache      Build without using cache
  -h, --help      Show this help

Variants (if none provided, all are built):
  base
  notebook
  codeserver
  desktop-xfce
  desktop-kde

Environment:
  COSIGN_KEY        Cosign private key content (PEM) stored directly in env; used if set
  COSIGN_KEY_FILE   Path to cosign private key file (default: ${COSIGN_KEY_FILE_DEFAULT})
  COSIGN_PASSWORD   Password for the private key (if the key is encrypted)

Examples:
  ./build/docker-build.sh                   # local build of all variants
  ./build/docker-build.sh base              # build only 'base'
  ./build/docker-build.sh notebook desktop-xfce
                                            # build two specific variants
  ./build/docker-build.sh --push base       # push + sign only 'base' variant
  COSIGN_KEY_FILE=/path/to/cosign.key ./build/docker-build.sh --push base
                                            # push + sign using key file
  COSIGN_KEY="\$(cat cosign.key)" ./build/docker-build.sh --push base
                                            # push + sign using key from env
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

# --- Entry point ---
Main "$@"
