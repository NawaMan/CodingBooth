#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Run wails-cross for one GOOS/GOARCH inside CodingBooth DinD.
#
# Bind-mounts of /home/coder/code do not work (DinD is a sibling). Named
# volumes + tar-over-stdin go through the API.
#
# Darwin/Windows: Zig in the host-arch wails-cross image.
# Linux other-arch: GTK CGO needs that arch's gcc + libgtk, so the image is
# rebuilt with --platform and run under QEMU. Using the amd64 image's gcc
# for GOARCH=arm64 fails assembling gcc_arm64.S.

set -euo pipefail

OS="${1:?usage: cross-docker.sh <darwin|linux|windows> <amd64|arm64>}"
ARCH="${2:?usage: cross-docker.sh <darwin|linux|windows> <amd64|arm64>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT"
VOL="wails-example-src"
APP_NAME="booth-counter"
DOCKER_DIR="$APP_DIR/build/docker"

host_m="$(uname -m)"
case "$host_m" in
    x86_64|amd64) host_goarch=amd64 ;;
    aarch64|arm64) host_goarch=arm64 ;;
    *) echo "unknown host arch: $host_m" >&2; exit 1 ;;
esac

IMG="wails-cross"
platform_args=()

# Ubuntu docker.io has no buildx. DOCKER_BUILDKIT=1 is a hard error, not a
# fallback: "BuildKit is enabled but the buildx component is missing".
unset DOCKER_BUILDKIT || true

# Classic docker + containerd snapshotter cannot COPY into a foreign-platform
# image (content digest not found / "does not provide the specified platform").
# RUN works. Rewrite COPY lines to `RUN echo b64 | base64 -d`.
dockerfile_without_copy() {
    local src="$1" dest="$2" ctx="$3" plat="$4"
    local line f d b64
    : > "$dest"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == 'FROM --platform=$TARGETPLATFORM golang:1.26-trixie' ]]; then
            printf 'FROM --platform=%s golang:1.26-trixie\n' "$plat" >> "$dest"
            continue
        fi
        if [[ "$line" =~ ^COPY[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            f="${BASH_REMATCH[1]}"
            d="${BASH_REMATCH[2]}"
            b64="$(base64 -w0 "$ctx/$f")"
            printf "RUN echo '%s' | base64 -d > %s && chmod +x %s\n" \
                "$b64" "$d" "$d" >> "$dest"
            continue
        fi
        printf '%s\n' "$line" >> "$dest"
    done < "$src"
}

if [[ "$OS" == "linux" && "$ARCH" != "$host_goarch" ]]; then
    IMG="wails-cross:${ARCH}"
    platform_args=(--platform "linux/${ARCH}")
    if ! docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMG" 2>/dev/null | grep -q "linux/${ARCH}"; then
        echo "→ installing qemu binfmt for linux/${ARCH}"
        docker run --privileged --rm tonistiigi/binfmt --install "$ARCH"
        echo "→ pulling golang:1.26-trixie for linux/${ARCH}"
        docker pull --platform "linux/${ARCH}" golang:1.26-trixie
        tmp_df="$(mktemp)"
        dockerfile_without_copy \
            "$DOCKER_DIR/Dockerfile.cross" "$tmp_df" "$DOCKER_DIR" "linux/${ARCH}"
        echo "→ building $IMG for linux/${ARCH} (QEMU; no COPY; no amd64 cache)"
        docker build \
            "${platform_args[@]}" \
            --build-arg "TARGETARCH=${ARCH}" \
            --pull \
            --no-cache \
            -t "$IMG" \
            -f "$tmp_df" \
            "$DOCKER_DIR"
        rm -f "$tmp_df"
        got="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMG")"
        if [[ "$got" != "linux/${ARCH}" ]]; then
            echo "built $IMG as $got, expected linux/${ARCH}" >&2
            exit 1
        fi
    fi
fi

mkdir -p "$APP_DIR/bin"
docker volume create "$VOL" >/dev/null

echo "→ packing $APP_DIR into volume $VOL"
tar -C "$APP_DIR" \
    --exclude='./bin' \
    --exclude='./frontend/node_modules' \
    --exclude='./frontend/dist' \
    --exclude='./.booth' \
    --exclude='./.cb-tests' \
    --exclude='./.task' \
    --exclude='./.git' \
    -cf - . \
  | docker run --rm -i --entrypoint tar -v "${VOL}:/app" wails-cross -xf - -C /app

echo "→ ${IMG} ${platform_args[*]:-} $OS $ARCH"
docker run --rm \
    "${platform_args[@]}" \
    -v "${VOL}:/app" \
    -e "APP_NAME=${APP_NAME}" \
    "$IMG" "$OS" "$ARCH"

EXT=""
[[ "$OS" == "windows" ]] && EXT=".exe"
ARTIFACT="${APP_NAME}-${OS}-${ARCH}${EXT}"

echo "→ copying bin/${ARTIFACT} back"
docker run --rm --entrypoint tar -v "${VOL}:/app" wails-cross -cf - -C /app/bin "$ARTIFACT" \
  | tar -xf - -C "$APP_DIR/bin"

echo "Built: $APP_DIR/bin/${ARTIFACT}"
ls -lh "$APP_DIR/bin/${ARTIFACT}"
