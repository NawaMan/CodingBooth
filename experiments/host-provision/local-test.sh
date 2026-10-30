#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# local-test.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Runs run.sh inside a throwaway plain ubuntu:26.04 container, standing in for
# a fresh machine or a runner: a sudo-capable user named like the target's
# (runner, uid 1001, for gha; owner, uid 1000, for host) and a copy of the repo
# where GitHub checks it out. Nothing from the booth image is used.
#
# The repo is copied in, not mounted: what the example builds (a CMake build/
# folder, say) stays in the throwaway container instead of landing in the
# checkout, where a cache made at this path breaks the next booth build. The
# copy is the files git tracks or would add (no ignored build output), limited
# to what the run reads: variants/, experiments/, docs/*.md, the example.
#
# Usage: local-test.sh gha|host [example-dir-relative-to-repo]
# Report: experiments/host-provision/.out/<example>/report-<target>.txt
# -----------------------------------------------------------------------------

set -euo pipefail

TARGET="${1:?usage: local-test.sh gha|host [example]}"
EXAMPLE_REL="${2:-examples/workspaces/go-example}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EX_NAME="$(basename "$EXAMPLE_REL")"
OUT="$HERE/.out/$EX_NAME"            # one folder per example, so runs can go in parallel
mkdir -p "$OUT"
rm -f "$OUT"/*-"$TARGET".* 2>/dev/null || true

case "$TARGET" in
  gha)  USER_NAME=runner UID_NUM=1001 ;;
  host) USER_NAME=owner  UID_NUM=1000 ;;
  *) echo "❌ target must be gha or host" >&2; exit 1 ;;
esac
WORK="/home/$USER_NAME/work/CodingBooth/CodingBooth"
NAME="cb-host-provision-exp-$TARGET-$EX_NAME"

docker rm -f "$NAME" >/dev/null 2>&1 || true
(cd "$REPO" && git ls-files -co --exclude-standard -z -- variants experiments 'docs/*.md' docs/favicon.png \
    README.md LICENSE version.txt "$EXAMPLE_REL" | tar --null -T - -cf -) |
docker run -i --rm --name "$NAME" \
  -v "$OUT:/out" \
  ubuntu:26.04 bash -c "
    set -euo pipefail
    mkdir -p '$WORK' && tar -xf - -C '$WORK'
    apt-get update -qq && apt-get install -y -qq sudo ca-certificates >/dev/null
    userdel -r ubuntu 2>/dev/null || true
    useradd -m -u $UID_NUM -s /bin/bash $USER_NAME
    echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME
    # The copy made the home before useradd did: give it the owner and skeleton a real one has.
    cp -rn /etc/skel/. /home/$USER_NAME/
    chown -R $USER_NAME:$USER_NAME /home/$USER_NAME
    cd '$WORK'
    runuser -u $USER_NAME -- env HOME=/home/$USER_NAME REPORT=/home/$USER_NAME/report.txt \
      '$WORK/experiments/host-provision/run.sh' $TARGET '$WORK/$EXAMPLE_REL' || echo 'run.sh exited non-zero'
    cp /home/$USER_NAME/report.txt /out/report-$TARGET.txt
    cp /home/$USER_NAME/report-tests.log /out/report-$TARGET-tests.log 2>/dev/null || true
    cp /tmp/go-test.log /tmp/go-build.log /out/ 2>/dev/null || true
    chown -R $(id -u):$(id -g) /out
    cp /tmp/startups.log /out/startups-$TARGET.log 2>/dev/null || true
  " 2>&1 | tee "$OUT/run-$TARGET.log"
