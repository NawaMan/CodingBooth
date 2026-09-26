#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# --engine picks the container engine binary (docker or podman; podman is
# experimental). Every case here sets the engine explicitly, so the result does
# not depend on which engines happen to be installed — the "docker missing, use
# podman" fallback is covered by Go unit tests, since it needs a PATH without docker.

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" test--engine-config.toml test--engine-config-docker.toml' EXIT

# Lines that start an engine command in the dryrun dump are "<engine> \".
engine_lines() { printf '%s\n' "$1" | grep -E '^(docker|podman) \\$' | sort -u | tr -d ' \\' | paste -sd, -; }

check() { # num desc expected-engines actual-output
  local num="$1" desc="$2" expect="$3" out="$4" got
  got="$(engine_lines "$out" || true)"
  if [[ "$got" == "$expect" ]]; then
    print_test_result "true" "$0" "$num" "$desc"
  else
    print_test_result "false" "$0" "$num" "$desc"
    echo "Expected engines: $expect"; echo "Actual engines:   $got"; echo "Output:"; echo "$out"
    exit 1
  fi
}

# 1. --engine docker
OUT=$(run_coding_booth --variant base --dryrun --engine docker 2>/dev/null || true)
check 1 "--engine docker prints only docker commands" "docker" "$OUT"

# 2. --engine podman
OUT=$(run_coding_booth --variant base --dryrun --engine podman 2>/dev/null || true)
check 2 "--engine podman prints only podman commands" "podman" "$OUT"

# 3. engine from a config file
printf 'engine = "podman"\n' > test--engine-config.toml
OUT=$(run_coding_booth --config test--engine-config.toml --variant base --dryrun 2>/dev/null || true)
check 3 "engine = \"podman\" in config.toml is honored" "podman" "$OUT"

# 4. engine from the environment
OUT=$(CB_ENGINE=podman run_coding_booth --variant base --dryrun 2>/dev/null || true)
check 4 "CB_ENGINE=podman is honored" "podman" "$OUT"

# 5. precedence: flag > config file > env
OUT=$(run_coding_booth --config test--engine-config.toml --variant base --dryrun --engine docker 2>/dev/null || true)
check 5 "--engine beats config.toml" "docker" "$OUT"

printf 'engine = "podman"\n' > test--engine-config-docker.toml
OUT=$(CB_ENGINE=docker run_coding_booth --config test--engine-config-docker.toml --variant base --dryrun 2>/dev/null || true)
check 6 "config.toml beats CB_ENGINE" "podman" "$OUT"

# 7. an unsupported engine is rejected, not passed through to exec
if ERR=$(run_coding_booth --variant base --dryrun --engine nerdctl 2>&1); then
  print_test_result "false" "$0" "7" "--engine nerdctl is rejected"
  echo "Output:"; echo "$ERR"
  exit 1
elif printf '%s\n' "$ERR" | grep -q 'invalid engine'; then
  print_test_result "true" "$0" "7" "--engine nerdctl is rejected"
else
  print_test_result "false" "$0" "7" "--engine nerdctl is rejected with a clear message"
  echo "Output:"; echo "$ERR"
  exit 1
fi

# 8. podman builds add --format docker (Buildah's OCI format ignores SHELL); docker builds do not
printf 'FROM scratch\n' > "$WORK/Dockerfile"
BUILD_ARGS=(--code "$WORK" --dockerfile "$WORK/Dockerfile" --variant base --dryrun)

OUT=$(run_coding_booth "${BUILD_ARGS[@]}" --engine podman 2>/dev/null || true)
if printf '%s\n' "$OUT" | tr -d '\\' | grep -Eq '^ *--format docker *$'; then
  print_test_result "true" "$0" "8" "podman build passes --format docker"
else
  print_test_result "false" "$0" "8" "podman build passes --format docker"
  echo "Output:"; echo "$OUT"
  exit 1
fi

OUT=$(run_coding_booth "${BUILD_ARGS[@]}" --engine docker 2>/dev/null || true)
if printf '%s\n' "$OUT" | grep -q -- '--format docker'; then
  print_test_result "false" "$0" "9" "docker build does not get --format docker"
  echo "Output:"; echo "$OUT"
  exit 1
else
  print_test_result "true" "$0" "9" "docker build does not get --format docker"
fi

# 10. rootless podman keeps the host UID inside the container; docker gets no userns flags.
# (Skipped for a root test runner: rootful podman needs neither.)
if [[ "$(id -u)" != "0" ]]; then
  OUT=$(run_coding_booth --variant base --dryrun --engine podman 2>/dev/null || true)
  if printf '%s\n' "$OUT" | grep -q -- '--userns=keep-id'; then
    print_test_result "true" "$0" "10" "rootless podman run adds --userns=keep-id"
  else
    print_test_result "false" "$0" "10" "rootless podman run adds --userns=keep-id"
    echo "Output:"; echo "$OUT"
    exit 1
  fi

  OUT=$(run_coding_booth --variant base --dryrun --engine docker 2>/dev/null || true)
  if printf '%s\n' "$OUT" | grep -q -- '--userns'; then
    print_test_result "false" "$0" "11" "docker run gets no --userns flag"
    echo "Output:"; echo "$OUT"
    exit 1
  else
    print_test_result "true" "$0" "11" "docker run gets no --userns flag"
  fi
fi

# 12. `booth build` takes --engine too (it parses its own flags)
mkdir -p "$WORK/buildproj/.booth"
printf 'FROM scratch\n' > "$WORK/buildproj/.booth/Dockerfile"
OUT=$(run_coding_booth build --code "$WORK/buildproj" --variant base --dryrun --engine podman 2>/dev/null || true)
if printf '%s\n' "$OUT" | grep -Eq '^podman \\$' && ! printf '%s\n' "$OUT" | grep -Eq '^docker \\$'; then
  print_test_result "true" "$0" "12" "booth build --engine podman prints podman commands"
else
  print_test_result "false" "$0" "12" "booth build --engine podman prints podman commands"
  echo "Output:"; echo "$OUT"
  exit 1
fi

# 13. podman gets the low-port sysctl Docker already applies; docker does not need it
OUT=$(run_coding_booth --variant base --dryrun --engine podman 2>/dev/null || true)
if printf '%s\n' "$OUT" | grep -q 'net.ipv4.ip_unprivileged_port_start=0'; then
  print_test_result "true" "$0" "13" "podman run lets coder bind low ports"
else
  print_test_result "false" "$0" "13" "podman run lets coder bind low ports"
  echo "Output:"; echo "$OUT"
  exit 1
fi
OUT=$(run_coding_booth --variant base --dryrun --engine docker 2>/dev/null || true)
if printf '%s\n' "$OUT" | grep -q 'ip_unprivileged_port_start'; then
  print_test_result "false" "$0" "14" "docker run has no low-port sysctl"
  echo "Output:"; echo "$OUT"
  exit 1
else
  print_test_result "true" "$0" "14" "docker run has no low-port sysctl"
fi

# 15. ...but not when the booth joins a sidecar's network namespace (--egress): Podman cannot set it there.
# --code points at a temp dir because --egress writes its generated policy files under the code directory.
mkdir -p "$WORK/egressproj"
OUT=$(run_coding_booth --code "$WORK/egressproj" --variant base --dryrun --engine podman --egress 2>/dev/null || true)
if printf '%s\n' "$OUT" | grep -q 'ip_unprivileged_port_start'; then
  print_test_result "false" "$0" "15" "podman --egress run skips the low-port sysctl"
  echo "Output:"; echo "$OUT"
  exit 1
else
  print_test_result "true" "$0" "15" "podman --egress run skips the low-port sysctl"
fi

# 16. --dind with --engine podman runs a nested-Podman sidecar in place of
# docker:dind (Phase 4, docs/PODMAN_SUPPORT.md), with its own experimental
# warning, rather than the outright refusal this used to be.
OUT=$(run_coding_booth --variant base --dryrun --engine podman --dind 2>&1)
if ! printf '%s\n' "$OUT" | grep -q -- 'Warning: --dind with --engine podman uses an experimental nested-Podman sidecar'; then
  print_test_result "false" "$0" "16" "podman --dind warns and runs a nested-Podman sidecar"
  echo "Missing the --dind/podman warning. Output:"; echo "$OUT"
  exit 1
elif ! printf '%s\n' "$OUT" | grep -q -- 'quay.io/podman/stable sh -c'; then
  print_test_result "false" "$0" "16" "podman --dind warns and runs a nested-Podman sidecar"
  echo "Missing the nested-Podman sidecar command. Output:"; echo "$OUT"
  exit 1
elif ! printf '%s\n' "$OUT" | grep -q -- 'exec podman system service --time=0 tcp://0.0.0.0:2375'; then
  print_test_result "false" "$0" "16" "podman --dind warns and runs a nested-Podman sidecar"
  echo "Missing the podman system service startup command. Output:"; echo "$OUT"
  exit 1
else
  print_test_result "true" "$0" "16" "podman --dind warns and runs a nested-Podman sidecar"
fi
