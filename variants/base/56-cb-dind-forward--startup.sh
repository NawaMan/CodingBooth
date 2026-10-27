#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# 56-cb-dind-forward--startup.sh
# --dind-isolation kata (experimental): the DinD sidecar is its own VM, so the
# booth no longer shares its network and localhost:<port> would miss a container
# the sidecar runs. The CLI names the sidecar in BOOTH_DIND_HOST (and lists the
# run-args publishes in BOOTH_DIND_FORWARD); booth--dind-forward puts each port
# the sidecar publishes back on loopback, so `curl localhost:8080` keeps working
# as it does with a plain --dind. Unset everywhere else: a no-op.
#
# Runs as coder, before booth-entry revokes sudo (BOOTH_SUDO=false); the
# forwarder runs as root so it can listen below 1024 (kind publishes 80/443).
# -----------------------------------------------------------------------------

# Best-effort: never take down container start.
set +e

[ -n "${BOOTH_DIND_HOST:-}" ] || exit 0

if ! command -v socat >/dev/null 2>&1 || ! command -v booth--dind-forward >/dev/null 2>&1; then
  echo "No socat/booth--dind-forward: reach DinD ports at ${BOOTH_DIND_HOST}:<port> instead of localhost"
  exit 0
fi

# shellcheck disable=SC2086 # BOOTH_DIND_FORWARD is a space-separated port list
sudo -n setsid booth--dind-forward "$BOOTH_DIND_HOST" ${BOOTH_DIND_FORWARD:-} </dev/null >/dev/null 2>&1 &
echo "Forwarding localhost to the ports the DinD sidecar ${BOOTH_DIND_HOST} publishes"
exit 0
