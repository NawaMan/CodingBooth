#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Report examples whose `env APT_SNAPSHOT=` pin sits before the base image's
# own archive snapshot — the other staleness ensure-fresh-image--source.sh
# does not cover, because rebuilding the image is not what goes stale here.
#
# The rule (release-push skill, "Apt snapshot pin"): an example's snapshot
# must never sit before the base's. A package with an exact-version dependency
# the base has already upgraded can't be satisfied from an older archive
# snapshot -- that's what broke systemlib-example on 2026-09-28
# (libcurl4-openssl-dev wanting a libcurl4t64 build the base no longer had).
#
# Only `install apt` lines actually consume the pin (apt--install.sh reads
# APT_SNAPSHOT; a setup script's own apt-get calls do not), so most examples'
# `env APT_SNAPSHOT=` stamp is unconsumed and a stale date there is harmless --
# this only reports the ones where it can actually break a build.
#
# This does not need re-deriving "what should the snapshot be" by hand: the
# base image now carries it as a real label (see the label_arg comment in
# build/docker-build.sh), baked in at build time regardless of whether that
# variant's own Dockerfile took APT_SNAPSHOT as a build-arg. Read it, don't
# guess it from today's date -- the two differ whenever the base was built on
# an earlier day than this check runs, or rebuilt same-version on a later day.
#
# This is report-only, not auto-fix: unlike a Docker image, fixing an example
# means editing tracked Boothfile/config.toml/.generated content, which
# should not happen as a silent side effect of running tests. See the fix
# command each report line prints (booth config --overwrite, never sed --
# see release-push's skill for why by hand breaks the .generated fingerprint).
# -----------------------------------------------------------------------------

_cas_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# base_apt_snapshot [<version>]: the base image's baked snapshot, or empty if
# there is no local base image to read it from (e.g. never built).
base_apt_snapshot() {
  local repo_root version
  repo_root="$(_cas_repo_root)"
  version="${1:-$(tr -d ' \t\n\r' < "${repo_root}/version.txt" 2>/dev/null)}"
  [[ -n "$version" ]] || return 1
  docker image inspect "nawaman/codingbooth:base-${version}" \
    --format '{{ index .Config.Labels "com.codingbooth.apt-snapshot" }}' 2>/dev/null || true
}

# report_apt_snapshot_drift: prints one line per example whose Boothfile both
# has an `install apt` line and an `env APT_SNAPSHOT=` older than the base
# image's. Silent when there is nothing to report (already up to date, or no
# local base image to compare against). Always returns 0 -- this informs,
# it never blocks a run.
report_apt_snapshot_drift() {
  [[ "${CB_NO_APT_SNAPSHOT_CHECK:-}" == "1" ]] && return 0
  command -v docker >/dev/null 2>&1 || return 0

  local repo_root base_snap
  repo_root="$(_cas_repo_root)"
  base_snap="$(base_apt_snapshot)"
  [[ -n "$base_snap" ]] || return 0

  local bf name example_snap found=false
  for bf in "${repo_root}"/examples/workspaces/*/.booth/Boothfile; do
    [[ -f "$bf" ]] || continue
    grep -q '^install apt' "$bf" || continue

    example_snap="$(grep -o 'APT_SNAPSHOT=[0-9]*T[0-9]*Z' "$bf" | head -1 | cut -d= -f2)"
    [[ -n "$example_snap" ]] || continue

    if [[ "$example_snap" < "$base_snap" ]]; then
      if [[ "$found" == false ]]; then
        echo "⚠️  APT_SNAPSHOT behind the base image (${base_snap}) in:"
        found=true
      fi
      name="$(basename "$(dirname "$(dirname "$bf")")")"
      echo "    - ${name} (${example_snap}) -- fix: (cd examples/workspaces/${name} && CB_APT_SNAPSHOT=${base_snap} \"\$REPO_ROOT/codingbooth\" config --no-tui --overwrite)"
    fi
  done
  return 0
}
