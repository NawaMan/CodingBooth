#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

# This script installs Debian/Ubuntu system packages via apt.
# Usage: apt--install.sh <package>[=<version>] [package...]
# Example: apt--install.sh htop
#          apt--install.sh jq htop=3.0.5-7
#
# Version pinning uses apt's native "name=version" syntax and is passed straight
# through to apt-get. A pinned version alone is fragile: the live archive keeps
# only the current version of most packages, so an old pin stops resolving once a
# newer one lands (see docs/REPRODUCIBILITY.md).
#
# Reproducibility: if APT_SNAPSHOT is set (a UTC snapshot id like 20260601T000000Z),
# every apt operation resolves against Ubuntu's archive snapshot for that instant,
# freezing transitive dependencies too. `booth config` stamps APT_SNAPSHOT with the
# configuration date. When APT_SNAPSHOT is empty/unset (e.g. a hand-written Boothfile),
# no --snapshot is passed and apt resolves against the live archive, as it does by
# default. The pin applies on amd64/i386 only — see the SNAPSHOT_ARGS block below.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# cb_retry retries the network-bound install below past a transient registry
# error (a 5xx, a dropped connection) and nothing else, so a bad package name
# still fails on the first attempt. The lib sits beside this script both in the
# image (/opt/codingbooth/setups/) and in the repo, so a host-run test finds it.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <package>[=<version>] [package...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No apt packages requested is a no-op, not an error: the *-pkg templates emit
# `install apt ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No apt packages requested; nothing to install."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Freeze the archive to a snapshot when APT_SNAPSHOT is set; otherwise let apt
# resolve against the live archive (no --snapshot).
#
# Ubuntu's snapshot service only mirrors the primary archive (archive/security.ubuntu.com,
# i.e. amd64 and i386) — snapshot.ubuntu.com refuses the ports paths, and apt ships no
# Acquire::Snapshots::URI::Host entry for ports.ubuntu.com. On every other architecture
# (arm64 on Apple Silicon, armhf, ppc64el, riscv64, s390x) apt's sources point at
# ports.ubuntu.com, so `--snapshot` silently fetches nothing during `update` and then
# resolves `install` against an empty index: every not-yet-installed package fails with
# "E: Unable to locate package". Drop the pin there and warn, so the build still works
# against the live archive instead of breaking.
SNAPSHOT_ARGS=()
PINNED=""
if [ -n "${APT_SNAPSHOT:-}" ]; then
    ARCH="$(dpkg --print-architecture)"
    case "$ARCH" in
        amd64|i386)
            echo "🧊 Pinning apt to snapshot ${APT_SNAPSHOT}"
            SNAPSHOT_ARGS=(--snapshot "${APT_SNAPSHOT}")
            PINNED=1
            ;;
        *)
            echo "⚠️  APT_SNAPSHOT=${APT_SNAPSHOT} ignored on ${ARCH}: Ubuntu's snapshot"
            echo "    service covers only the primary archive (amd64/i386); ${ARCH} installs"
            echo "    from ports.ubuntu.com, which has no snapshots. Resolving against the"
            echo "    live archive — this build is not frozen in time."
            ;;
    esac
fi

# A pin older than the image's own snapshot (CB_IMAGE_APT_SNAPSHOT, set by the base
# image's build) can make an install impossible: the image already has newer
# builds of some packages, apt will not downgrade them, and an older -dev package
# needing an exact version of one of them cannot be satisfied. apt's own message
# reads like a broken archive ("Depends: libsqlite3-0 (= …7) but …8 is to be
# installed"), so say what it really is — up front, and with the fix if it fails.
OLDER_THAN_IMAGE=""
if [ -n "$PINNED" ] && [ -n "${CB_IMAGE_APT_SNAPSHOT:-}" ] \
        && [[ "$APT_SNAPSHOT" < "$CB_IMAGE_APT_SNAPSHOT" ]]; then
    OLDER_THAN_IMAGE=1
    echo "⚠️  APT_SNAPSHOT=${APT_SNAPSHOT} is older than this image's snapshot (${CB_IMAGE_APT_SNAPSHOT})."
    echo "    A package that needs an exact version of one the image already has newer"
    echo "    will not install."
fi

# apt-get update exits 0 even when snapshot.ubuntu.com 502/503s
# ("W: Failed to fetch … ignored"). cb_retry then sees success and does not
# retry; the following install dies with "Unable to locate package", which is
# deliberately not retried. Fail the update in that case so the existing
# retry actually runs (apt-example / turtle-example / systemlib-example).
apt_get_update() {
    local log rc
    log="$(mktemp)"
    rc=0
    apt-get update "$@" >"$log" 2>&1 || rc=$?
    cat "$log"
    if [ "$rc" -eq 0 ] && grep -qiE 'Failed to fetch|[45][0-9]{2}[[:space:]]+(Bad Gateway|Service Unavailable|Too Many Requests)' "$log"; then
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
    return "$rc"
}

# SNAPSHOT_ARGS is empty where the pin does not apply (arm64), and bash 3.2 — what
# macOS ships, and what the host-side tests run this with — calls an empty
# "${arr[@]}" unbound under `set -u`; this form expands to nothing instead.
cb_retry apt_get_update ${SNAPSHOT_ARGS[@]+"${SNAPSHOT_ARGS[@]}"}
if ! cb_retry apt-get install -y --no-install-recommends ${SNAPSHOT_ARGS[@]+"${SNAPSHOT_ARGS[@]}"} "$@"; then
    if [ -n "$OLDER_THAN_IMAGE" ]; then
        echo "" >&2
        echo "❌ apt could not install from snapshot ${APT_SNAPSHOT}: it is older than this" >&2
        echo "   image's snapshot (${CB_IMAGE_APT_SNAPSHOT}), and apt cannot downgrade packages" >&2
        echo "   the image already has." >&2
        echo "   Fix: booth config --apt-snapshot ${CB_IMAGE_APT_SNAPSHOT}   (this image's snapshot)" >&2
        echo "    or: booth config --apt-snapshot today" >&2
        echo "   then build the booth again." >&2
    fi
    exit 1
fi
rm -rf /var/lib/apt/lists/*
