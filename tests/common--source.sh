#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Common utilities for unit tests

# Host OS tag matching the codingbooth CLI's HOST_OS env var.
# Tests use this in their expected-output fixtures.
case "$(uname -s)" in
  Linux*)               HOST_OS="LIN" ;;
  Darwin*)              HOST_OS="MAC" ;;
  MINGW*|MSYS*|CYGWIN*) HOST_OS="WIN" ;;
  *)                    HOST_OS="$(uname -s)" ;;
esac
export HOST_OS

# Opt a test into building against a locally-rebuilt base image instead of the
# upstream nawaman/codingbooth Hub image. Use this when the test triggers a
# Boothfile build that relies on a setup-script fix that hasn't shipped to
# Docker Hub yet (e.g. clang/swift/elm arm64 workarounds).
#
# Why this matters: BuildKit's `# syntax=docker/dockerfile:1.7` frontend
# always resolves a `FROM nawaman/codingbooth:...` tag to the upstream
# registry digest, even when an identically-named image exists locally. Naming
# the local image under a repo that doesn't exist on Docker Hub
# (cb-local/codingbooth) sidesteps that resolution.
#
# Scoping: the export lives in the test script's process; each test is
# launched in a subshell by the suite runner, so the override does NOT leak
# into sibling tests. If a single test needs to revert mid-run (e.g. one
# build step should use the local image and a later one should hit Docker
# Hub), call `restore_default_base_image` between them.
#
# Usage (call once near the top of the test, after `source ../../common--source.sh`):
#   use_local_base_image || exit 0    # skips if local image not present
use_local_base_image() {
  local version="${1:-}"
  if [[ -z "$version" ]]; then
    local booth_path script_dir check_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    check_dir="$script_dir"
    for _ in 1 2 3 4 5; do
      if [[ -f "$check_dir/codingbooth" && -x "$check_dir/codingbooth" ]]; then
        booth_path="$check_dir/codingbooth"
        break
      fi
      check_dir="$(dirname "$check_dir")"
    done
    if [[ -n "${booth_path:-}" ]]; then
      version=$("$booth_path" version 2>/dev/null | tail -1 | sed 's/.*: //')
    fi
  fi
  [[ -z "$version" || "$version" == "dev" ]] && version="latest"

  local img="cb-local/codingbooth:base-${version}"
  if docker image inspect "$img" >/dev/null 2>&1; then
    export CB_PREBUILD_REPO="cb-local/codingbooth"
    return 0
  fi

  echo "SKIP: ${img} not built locally; tag a rebuilt base image as cb-local/codingbooth:base-${version} to enable this test." >&2
  return 1
}

# Counterpart to use_local_base_image — unsets the env var so subsequent
# booth invocations in the same script fall back to the default Hub repo.
restore_default_base_image() {
  unset CB_PREBUILD_REPO
}

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
  COLOR_CMD='\033[1;36m'    # Cyan bold for commands
  COLOR_BOOTH='\033[1;33m'  # Yellow bold for codingbooth
  COLOR_RESET='\033[0m'
else
  COLOR_CMD=''
  COLOR_BOOTH=''
  COLOR_RESET=''
fi

# Emit a command trace to stderr, colorized only when stderr is a terminal.
# The COLOR_* vars above are chosen from stdout, but the trace goes to stderr:
# tests capture it with `2>&1` and drop it with a `^> `-anchored match, which an
# ANSI color prefix would silently defeat.
# Usage: trace_cmd <sgr-code> <text...>
trace_cmd() {
  local sgr="$1"; shift
  if [[ -t 2 ]]; then
    printf '\033[%sm%s\033[0m\n' "$sgr" "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

# Run a command with visible output of what's being executed
# Usage: run_cmd <command...>
# Example: run_cmd ls -la
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
run_cmd() {
  trace_cmd '1;36' "> $*"
  "$@"
}

# Run a codingbooth command with highlighted output
# Usage: run_coding_booth [args...]
# Example: run_coding_booth --variant base -- echo hello
# The path to codingbooth is auto-detected relative to the test script
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
#
# Quoting after `--`: everything after `--` is joined with spaces into ONE shell
# command line and run via `bash -lc` in the container (see docs/BOOTH_RUN.md).
# Argument boundaries do NOT survive that join, so pass the command as a single
# quoted argument:
#
#     run_coding_booth -- 'cowsay hello'                       # ✓
#     run_coding_booth -- 'gem list colorize | grep colorize'  # ✓ (pipeline in container)
#     run_coding_booth -- bash -lc 'cowsay hello'              # ✗ flattens to: bash -lc cowsay hello
#
# The third form silently runs `cowsay` with $0="hello" instead of failing loudly,
# which is how it went unnoticed in 19 tests. There is no need to add your own
# `bash -lc` — the wrapper already supplies a login shell.
run_coding_booth() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

  # Find the codingbooth binary relative to the test location.
  # Use `-f` before `-x` so we don't accidentally match a directory of the same name
  # on case-insensitive filesystems (e.g. macOS: -x /path/codingbooth would otherwise
  # match the CodingBooth project directory itself, since directories are "executable").
  local booth_path=""
  local check_dir="$script_dir"
  for _ in 1 2 3 4 5; do
    if [[ -f "$check_dir/codingbooth" && -x "$check_dir/codingbooth" ]]; then
      booth_path="$check_dir/codingbooth"
      break
    fi
    check_dir="$(dirname "$check_dir")"
  done

  if [[ -z "$booth_path" ]]; then
    echo "ERROR: Could not find codingbooth" >&2
    return 1
  fi

  # When running a dev build, default to --version latest so prebuilt images resolve.
  # Only inject for run-like invocations, not for subcommands like list/start/stop/etc.
  local version_args=()
  local cb_version
  cb_version=$("$booth_path" version 2>/dev/null | tail -1 | sed 's/.*: //')
  if [[ "$cb_version" == "dev" ]]; then
    # Check if the first arg is a non-run subcommand — skip --version injection for those
    local first_arg="${1:-}"
    local is_subcommand=false
    case "$first_arg" in
      list|start|stop|restart|remove|prune|shell|exec|message|example|template|config|build|version|help|--help|-h)
        is_subcommand=true ;;
    esac

    if [[ "$is_subcommand" == false ]]; then
      # Only inject if the caller didn't already pass --version (before --)
      local has_version=false
      for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then break; fi
        if [[ "$arg" == "--version" ]]; then has_version=true; break; fi
      done
      if [[ "$has_version" == false ]]; then
        version_args=(--version latest)
      fi
    fi
  fi

  trace_cmd '1;33' "> codingbooth $*"
  # Safe expansion: avoids "unbound variable" under `set -u` with Bash 3.2 when the array is empty.
  "$booth_path" ${version_args[@]+"${version_args[@]}"} "$@"
}

# Get the version reported by the booth binary itself, so tests stay correct
# even when version.txt has been bumped but the binary hasn't been rebuilt yet.
get_booth_version() {
  run_coding_booth version 2>/dev/null | tail -1 | sed 's/.*: //'
}

# capture_codingbooth: run codingbooth, capture stdout, retry once on
# empty/failed output. Useful inside full-suite runs where rapid container
# spin-up/down occasionally produces a transient empty result that succeeds
# on retry. Pass shell pipeline transforms via $1 (e.g. "head -1", "tail -1").
# Defaults to "cat".
#
# Stderr is discarded by default. Set CB_STDERR_LOG to a writable file path to
# append it instead — worth doing for tests whose booth run includes an image
# build, since a build failure otherwise leaves no trace of *why* it failed.
# Each attempt is preceded by a marker line so the two retries stay separable.
# The caller is responsible for creating the log's parent directory.
#
# Usage:
#   ACTUAL=$(capture_codingbooth "head -1" --silence-build -- gcc --version)
capture_codingbooth() {
  local pipeline="${1:-cat}"
  shift
  local errdest="${CB_STDERR_LOG:-/dev/null}"
  local out

  _capture_attempt() {
    local n="$1"; shift
    if [[ "$errdest" != "/dev/null" ]]; then
      echo "=== capture_codingbooth attempt ${n}: codingbooth $* ===" >>"$errdest"
    fi
  }

  _capture_attempt 1 "$@"
  out=$(run_coding_booth "$@" 2>>"$errdest" | eval "$pipeline") || out=""
  if [[ -z "$out" ]]; then
    sleep 2
    _capture_attempt 2 "$@"
    out=$(run_coding_booth "$@" 2>>"$errdest" | eval "$pipeline") || out=""
  fi
  printf '%s\n' "$out"
}

# Normalize output for cross-platform comparison
# - Strips .exe extension from binary name
# - Converts Windows backslashes to forward slashes
# - Removes single quotes around Windows paths in -v mounts
# - Normalizes MSYS paths (/c/Users → C:/Users)
# - Masks UID/GID values to XXXXX for environment independence
normalize_output() {
    sed -E \
        -e 's/workspace\.exe/workspace/g' \
        -e 's|\\|/|g' \
        -e "s|-v '([^']+)'|-v \1|g" \
        -e 's|/c/|C:/|gi' \
        -e 's|/C/|C:/|g' \
        -e "s/HOST_UID=[0-9]+/HOST_UID=XXXXX/g" \
        -e "s/HOST_GID=[0-9]+/HOST_GID=XXXXX/g" \
        -e "s/HOST_UID:[[:space:]]+[0-9]+/HOST_UID:       XXXXX/g" \
        -e "s/HOST_GID:[[:space:]]+[0-9]+/HOST_GID:       XXXXX/g" \
        -e "s/cb\.created-at=[0-9T:-]+Z/cb.created-at=XXXXX/g"
}

script_relative_path() {
  local script_abs="${1:-$0}"
  local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  script_abs=$(realpath "$script_abs")
  root=$(realpath "$root")
  echo "${script_abs#${root}/tests/}"
}

# Print standardized test result
# Usage: print_test_result <success> <script_path> <test_number> <description>
#   success: "true" or "false"
#   script_path: path to test script (usually $0)
#   test_number: test number
#   description: test description
print_test_result() {
  local success="$1"
  local script_path="$2"
  local test_number="$3"
  local description="$4"
  
  local relative_path=$(script_relative_path "$script_path")
  local icon="✅"
  
  if [[ "$success" != "true" ]]; then
    icon="❌"
  fi
  
  echo "${icon} ${relative_path}: Test ${test_number}: ${description}"
}
