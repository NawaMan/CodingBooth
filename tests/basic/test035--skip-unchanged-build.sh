#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# A start whose image is already built from the same inputs skips `docker build`.
#
# Even a fully cached build contacts Docker Hub first -- for the dockerfile
# frontend and the FROM tag -- so during a registry outage a booth whose image
# was already built would not start. The build is now fingerprinted (the
# Dockerfile, build args, base image ID, and every COPY source), the fingerprint
# is stored as the cb.fingerprint image label, and a matching label skips the
# build entirely.
#
# Asserts: the first start builds; an unchanged second start skips; editing a
# copied input (.booth/setups/) builds again; the start after that skips; and a
# skipped start, traced through a `docker` shim, makes no build or pull call.

set -euo pipefail

source ../common--source.sh

BOOTH_BIN="$(find_local_booth_build)" || {
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
}

PROJECT="cb-skip-build-$$"
WORK_DIR="$(mktemp -d)"
CODE="$WORK_DIR/$PROJECT"
IMAGE="codingbooth-local:${PROJECT}-base-$(get_booth_version)"

cleanup() {
  docker image rm -f "$IMAGE" > /dev/null 2>&1 || true
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  return 0
}
trap cleanup EXIT

mkdir -p "$CODE/.booth/setups"
printf '# syntax=codingbooth/boothfile:1\nrun echo fingerprint > /tmp/fingerprint\n' > "$CODE/.booth/Boothfile"
printf '#!/bin/bash\necho demo\n' > "$CODE/.booth/setups/demo--setup.sh"

# Prints the Info lines and the command output of one start.
start_booth() {
  "$BOOTH_BIN" run --code "$CODE" -- 'echo OUT=$(cat /tmp/fingerprint)' 2>&1 || true
}

check() {
  local num="$1" desc="$2" output="$3" want="$4" unwanted="$5"
  if grep -qF "$want" <<< "$output" && ! grep -qF "$unwanted" <<< "$output" \
     && grep -qF "OUT=fingerprint" <<< "$output"; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc"
    printf '%s\n' "$output" | tail -20 | sed 's/^/  /'
    exit 1
  fi
}

check 1 "First start builds the image" \
  "$(start_booth)" "building local image" "skipping the build"

LABEL="$(docker image inspect --format '{{index .Config.Labels "cb.fingerprint"}}' "$IMAGE" 2>/dev/null || true)"
if [[ "$LABEL" =~ ^[0-9a-f]{64}$ ]]; then
  print_test_result "true" "$0" "2" "Image carries the cb.fingerprint label"
else
  print_test_result "false" "$0" "2" "Image carries the cb.fingerprint label (got '$LABEL')"
  exit 1
fi

check 3 "Unchanged second start skips the build" \
  "$(start_booth)" "skipping the build" "building local image"

echo '# edited' >> "$CODE/.booth/setups/demo--setup.sh"
check 4 "Editing a copied setup script builds again" \
  "$(start_booth)" "building local image" "skipping the build"

check 5 "The start after the rebuild skips again" \
  "$(start_booth)" "skipping the build" "building local image"

# --- A skipped start makes no registry call ----------------------------------
# The point of the skip is starting while Docker Hub is down, and the "skipping"
# message alone does not prove that: a later change could add a pull, or a
# build that hits the cache, back into the start. So log every engine command
# through a `docker` shim on PATH and assert that none of them can reach a
# registry. The remaining calls (info, image inspect, ps, run on a present
# image) read only the local engine.
SHIM_DIR="$WORK_DIR/shim"
CALLS="$WORK_DIR/docker-calls.log"
# type -P, not `command -v`: the suite wraps docker in a shell function on
# Windows (see common--source.sh), and `command -v` would name that function
# rather than the binary this shim has to forward to.
REAL_DOCKER="$(type -P docker)"
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/docker" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$CALLS"
exec "$REAL_DOCKER" "\$@"
EOF
chmod +x "$SHIM_DIR/docker"

# booth is a Windows program here, and it resolves `docker` the way Windows
# does: through PATHEXT. The extensionless script above is not an executable to
# it — it walked past the shim to the real docker.exe, the log stayed empty, and
# the check below reported a bypassed shim. A .cmd in the same directory is
# found first (PATH order wins before the extension list), and Docker Desktop
# ships docker.exe beside the POSIX `docker` wrapper the shell uses.
if [[ "$HOST_OS" == "WIN" ]]; then
  CALLS_WIN="$(host_path "$WORK_DIR" | tr '/' '\\')\\$(basename "$CALLS")"
  REAL_DOCKER_WIN="$(host_path "$(dirname "$REAL_DOCKER")" | tr '/' '\\')\\docker.exe"
  {
    printf '@echo off\r\n'
    printf '>>"%s" echo %%*\r\n' "$CALLS_WIN"
    printf '"%s" %%*\r\n' "$REAL_DOCKER_WIN"
  } > "$SHIM_DIR/docker.cmd"
fi
: > "$CALLS"

OUTPUT="$(PATH="$SHIM_DIR:$PATH" "$BOOTH_BIN" run --code "$CODE" -- 'echo OUT=$(cat /tmp/fingerprint)' 2>&1 || true)"
check 6 "Traced start skips the build" "$OUTPUT" "skipping the build" "building local image"

# An empty log means the shim was bypassed, and the next check would pass
# without having looked at anything.
if grep -q '^run ' "$CALLS"; then
  print_test_result "true" "$0" "7" "Engine calls were traced through the shim"
else
  print_test_result "false" "$0" "7" "Engine calls were traced through the shim (log has no 'run')"
  sed 's/^/  /' "$CALLS"
  exit 1
fi

REGISTRY_CALLS="$(grep -E '^(build|buildx|pull|image pull|image build|builder|login|manifest|search) ' "$CALLS" || true)"
if [[ -z "$REGISTRY_CALLS" ]]; then
  print_test_result "true" "$0" "8" "Skipped start makes no build, pull, or other registry call"
else
  print_test_result "false" "$0" "8" "Skipped start makes no build, pull, or other registry call"
  printf '%s\n' "$REGISTRY_CALLS" | cut -c1-200 | sed 's/^/  /'
  exit 1
fi
