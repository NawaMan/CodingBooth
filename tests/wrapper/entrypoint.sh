#!/usr/bin/env bash
# Entrypoint for the booth-wrapper test image.
# Starts dockerd unless NO_DIND=1 is set, then execs the given command
# (default: bash).
set -euo pipefail

if [[ "${NO_DIND:-0}" != "1" ]]; then
    # dockerd needs root; this image's sudoers grants NOPASSWD to tester.
    # fuse-overlayfs avoids the "overlay on overlay" mount failure that hits
    # when the host's /var/lib/docker is already on overlay2.
    sudo -n nohup dockerd \
        --host=unix:///var/run/docker.sock \
        --storage-driver=fuse-overlayfs \
        > /tmp/dockerd.log 2>&1 &

    # Wait for the daemon to come up (max ~15s).
    for _ in $(seq 1 50); do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 0.3
    done

    if ! docker info >/dev/null 2>&1; then
        echo "dockerd failed to start within 15s. Last log lines:" >&2
        tail -n 30 /tmp/dockerd.log >&2 || true
        echo "" >&2
        echo "If you're seeing iptables/cgroup errors, make sure the container" >&2
        echo "was started with --privileged." >&2
        exit 1
    fi
fi

exec "$@"
