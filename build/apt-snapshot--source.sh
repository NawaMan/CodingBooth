#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Which Ubuntu archive snapshot docker-build.sh builds the images against.
#
# Sourced by build/docker-build.sh, and by tests/setups/test--apt-snapshot-source.sh
# so the choice and its checks are tested without building an image.
#
# First match wins:
#
#   1. CB_APT_SNAPSHOT   — an id, or `today`. The release workflow sets it, once
#                          per release, for every build job (see
#                          .github/workflows/publish-docker-images.yaml).
#   2. apt-snapshot.txt  — the id that workflow pinned and committed for the last
#                          release. A local rebuild of a release commit then gets
#                          the archive that release was actually built against,
#                          not "whatever today is".
#   3. today             — UTC, day granularity; only when there is no pin file.
#
# The id format and its checks match `booth config --apt-snapshot`
# (cli/src/pkg/boothinit/aptsnapshot). An image is always pinned, so unlike there,
# `none` is refused.

APT_SNAPSHOT_FILE="apt-snapshot.txt"
APT_SNAPSHOT_EARLIEST="20230301T000000Z"   # the first snapshot Ubuntu's service has

# apt_snapshot_check <id>: prints why <id> cannot be used, or nothing when it can.
apt_snapshot_check() {
  local id="$1"
  if [[ ! "$id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
    echo "\"${id}\" is not a snapshot id — the format is YYYYMMDDTHHMMSSZ in UTC, e.g. 20260601T000000Z"
    return
  fi
  # A real date: GNU date first, then BSD (macOS). Either one reformats the id
  # back to itself only when every field was in range.
  local back
  back="$(date -u -d "${id:0:4}-${id:4:2}-${id:6:2} ${id:9:2}:${id:11:2}:${id:13:2}" +%Y%m%dT%H%M%SZ 2>/dev/null \
       || date -u -j -f %Y%m%dT%H%M%SZ "$id" +%Y%m%dT%H%M%SZ 2>/dev/null)" || true
  if [[ "$back" != "$id" ]]; then
    echo "\"${id}\" is not a real date and time"
    return
  fi
  if [[ "$id" < "$APT_SNAPSHOT_EARLIEST" ]]; then
    echo "\"${id}\" is before ${APT_SNAPSHOT_EARLIEST}, the first snapshot Ubuntu has"
    return
  fi
  if [[ "$id" > "$(date -u +%Y%m%dT%H%M%SZ)" ]]; then
    echo "\"${id}\" is in the future — no snapshot exists for it yet"
  fi
}

# resolve_apt_snapshot: sets APT_SNAPSHOT (the id) and APT_SNAPSHOT_FROM (where it
# came from). On a value that cannot be used, prints what is wrong and how to fix
# it to stderr and returns 1.
resolve_apt_snapshot() {
  local today fix problem
  today="$(date -u +%Y%m%d)T000000Z"

  if [[ -n "${CB_APT_SNAPSHOT:-}" ]]; then
    APT_SNAPSHOT="$CB_APT_SNAPSHOT"
    APT_SNAPSHOT_FROM="CB_APT_SNAPSHOT"
    fix="Unset CB_APT_SNAPSHOT to use ${APT_SNAPSHOT_FILE}, or set it to a snapshot id (e.g. 20260601T000000Z) or today."
    case "${APT_SNAPSHOT,,}" in
      today) APT_SNAPSHOT="$today" ;;
      none)
        echo "❌ CB_APT_SNAPSHOT=none: images are always built against a snapshot." >&2
        echo "   ${fix}" >&2
        return 1 ;;
    esac
  elif [[ -s "$APT_SNAPSHOT_FILE" ]]; then
    APT_SNAPSHOT="$(tr -d ' \t\r\n' < "$APT_SNAPSHOT_FILE")"
    APT_SNAPSHOT_FROM="$APT_SNAPSHOT_FILE"
    fix="The release workflow writes ${APT_SNAPSHOT_FILE}; restore it with \`git checkout -- ${APT_SNAPSHOT_FILE}\`, or override it with CB_APT_SNAPSHOT=<id|today>."
  else
    APT_SNAPSHOT="$today"
    APT_SNAPSHOT_FROM="today"
    return 0
  fi

  problem="$(apt_snapshot_check "$APT_SNAPSHOT")"
  if [[ -n "$problem" ]]; then
    echo "❌ ${APT_SNAPSHOT_FROM}: ${problem}" >&2
    echo "   ${fix}" >&2
    return 1
  fi
}
