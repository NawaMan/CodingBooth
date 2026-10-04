#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# --engine apple runs Apple container, whose CLI (`container`) is not
# Docker-compatible, so the CLI rewrites each call for it: queries become
# `container ls --all --format json` answered in Go, and run flags with no
# Apple equivalent are dropped (the ones the CLI adds itself) or refused. See
# docs/CONTAINER_SUPPORT.md. The rendering of that JSON is covered by the Go
# unit tests in cli/src/pkg/docker/apple_engine_test.go.

CONFIG="test--engine-apple-config.toml"
trap 'rm -f "$CONFIG"' EXIT

pass() { print_test_result "true"  "$0" "$1" "$2"; }
fail() { print_test_result "false" "$0" "$1" "$2"; echo "Output:"; echo "$3"; exit 1; }

# Lines that start an engine command in the dryrun dump are "<binary> \".
engine_lines() { printf '%s\n' "$1" | grep -E '^(docker|podman|container) \\$' | sort -u | tr -d ' \\' | paste -sd, -; }

OUT=$(run_coding_booth --variant base --dryrun --engine apple 2>/dev/null || true)

# 1. --engine apple runs only the container CLI
if [[ "$(engine_lines "$OUT" || true)" == "container" ]]; then
  pass 1 "--engine apple prints only container commands"
else
  fail 1 "--engine apple prints only container commands" "$OUT"
fi

# 2. the binary name is not an engine name
if ERR=$(run_coding_booth --variant base --dryrun --engine container 2>&1); then
  fail 2 "--engine container is rejected (the engine is apple)" "$ERR"
elif printf '%s\n' "$ERR" | grep -q 'invalid engine "container" (supported: docker, podman, apple)'; then
  pass 2 "--engine container is rejected (the engine is apple)"
else
  fail 2 "--engine container is rejected with a clear message" "$ERR"
fi

# 3. the name check is a JSON listing, not docker's ps --filter/--format
if printf '%s\n' "$OUT" | grep -Eq '^ *ls --all --format json *$' && ! printf '%s\n' "$OUT" | grep -q -- '--filter'; then
  pass 3 "apple queries list JSON instead of ps --filter"
else
  fail 3 "apple queries list JSON instead of ps --filter" "$OUT"
fi

# 4. flags the CLI adds that Apple container lacks are dropped, not passed through
if printf '%s\n' "$OUT" | grep -Eq -- '--add-host|--pull'; then
  fail 4 "apple run has no --add-host / --pull" "$OUT"
else
  pass 4 "apple run has no --add-host / --pull"
fi

# 5. the booth still gets its port and labels
if printf '%s\n' "$OUT" | grep -q -- "-p 127.0.0.1:" && printf '%s\n' "$OUT" | grep -q "cb.managed=true"; then
  pass 5 "apple run keeps the port mapping and lifecycle labels"
else
  fail 5 "apple run keeps the port mapping and lifecycle labels" "$OUT"
fi

# 6. the booth knows which engine started it
if printf '%s\n' "$OUT" | grep -q "BOOTH_ENGINE=apple"; then
  pass 6 "BOOTH_ENGINE=apple is passed into the booth"
else
  fail 6 "BOOTH_ENGINE=apple is passed into the booth" "$OUT"
fi

# 7-8. --dind and --egress are refused up front — before the egress defaults
# write .booth/egress/ into the project
for flag in --dind --egress; do
  num=$([[ "$flag" == "--dind" ]] && echo 7 || echo 8)
  had_booth_dir=$([[ -e .booth ]] && echo yes || echo no)
  if ERR=$(run_coding_booth --variant base --dryrun --engine apple "$flag" --dind-allowed 2>&1); then
    fail "$num" "$flag is refused on engine apple" "$ERR"
  elif [[ "$had_booth_dir" == "no" && -e .booth ]]; then
    rm -rf .booth
    fail "$num" "$flag refusal leaves no .booth/ behind" "$ERR"
  elif printf '%s\n' "$ERR" | grep -q -- "$flag is not supported on engine apple"; then
    pass "$num" "$flag is refused on engine apple"
  else
    fail "$num" "$flag is refused on engine apple with a clear message" "$ERR"
  fi
done

# 9. a run-arg with no Apple equivalent is refused, not silently dropped
printf 'run-args = "--privileged"\n' > "$CONFIG"
if ERR=$(run_coding_booth --config "$CONFIG" --variant base --dryrun --engine apple --privileged-allowed 2>&1); then
  fail 9 "--privileged run-arg is refused on engine apple" "$ERR"
elif printf '%s\n' "$ERR" | grep -q -- "--privileged is not supported on engine apple"; then
  pass 9 "--privileged run-arg is refused on engine apple"
else
  fail 9 "--privileged run-arg is refused on engine apple with a clear message" "$ERR"
fi

# 10. host.docker.internal has no --add-host here, so the booth is handed the
# gateway address instead (the dryrun default), and asked to map the name
if printf '%s\n' "$OUT" | grep -q "BOOTH_HOST_NAME=192.168.64.1" \
  && printf '%s\n' "$OUT" | grep -q "BOOTH_HOST_GATEWAY=192.168.64.1"; then
  pass 10 "apple passes the gateway as BOOTH_HOST_NAME and BOOTH_HOST_GATEWAY"
else
  fail 10 "apple passes the gateway as BOOTH_HOST_NAME and BOOTH_HOST_GATEWAY" "$OUT"
fi

# 11. docker keeps the name and never asks for the mapping
DOCKER_OUT=$(run_coding_booth --variant base --dryrun --engine docker 2>/dev/null || true)
if printf '%s\n' "$DOCKER_OUT" | grep -q "BOOTH_HOST_NAME=host.docker.internal" \
  && ! printf '%s\n' "$DOCKER_OUT" | grep -q "BOOTH_HOST_GATEWAY"; then
  pass 11 "docker keeps BOOTH_HOST_NAME=host.docker.internal and no BOOTH_HOST_GATEWAY"
else
  fail 11 "docker keeps BOOTH_HOST_NAME=host.docker.internal and no BOOTH_HOST_GATEWAY" "$DOCKER_OUT"
fi

# 12. --apple-low-ports: coder may open ports below 1024 on Apple container,
# which (unlike Docker) does not allow them by default. booth-entry reads the
# env var; shell/exec read the label.
LOW=$(run_coding_booth --variant base --dryrun --engine apple --apple-low-ports 2>/dev/null || true)
if printf '%s\n' "$LOW" | grep -q "BOOTH_LOW_PORTS=true" \
  && printf '%s\n' "$LOW" | grep -q "cb.apple-low-ports=true" \
  && ! printf '%s\n' "$LOW" | grep -q -- "--cap-add"; then
  pass 12 "--apple-low-ports passes BOOTH_LOW_PORTS and the label, and adds no --cap-add"
else
  fail 12 "--apple-low-ports passes BOOTH_LOW_PORTS and the label, and adds no --cap-add" "$LOW"
fi

# 12b-c. the same from the environment and from config.toml
ENVLOW=$(CB_APPLE_LOW_PORTS=true run_coding_booth --variant base --dryrun --engine apple 2>/dev/null || true)
if printf '%s\n' "$ENVLOW" | grep -q "BOOTH_LOW_PORTS=true"; then
  pass 12b "CB_APPLE_LOW_PORTS=true turns it on"
else
  fail 12b "CB_APPLE_LOW_PORTS=true turns it on" "$ENVLOW"
fi
printf 'apple-low-ports = true\n' > "$CONFIG"
CFGLOW=$(run_coding_booth --config "$CONFIG" --variant base --dryrun --engine apple 2>/dev/null || true)
if printf '%s\n' "$CFGLOW" | grep -q "BOOTH_LOW_PORTS=true"; then
  pass 12c "apple-low-ports = true in config.toml turns it on"
else
  fail 12c "apple-low-ports = true in config.toml turns it on" "$CFGLOW"
fi

# 13. without the flag, nothing of it
if printf '%s\n' "$OUT" | grep -q "BOOTH_LOW_PORTS\|cb.apple-low-ports"; then
  fail 13 "without --apple-low-ports there is no BOOTH_LOW_PORTS or label" "$OUT"
else
  pass 13 "without --apple-low-ports there is no BOOTH_LOW_PORTS or label"
fi

# 14. on docker the flag is ignored, and says so
DLOW=$(run_coding_booth --variant base --dryrun --engine docker --apple-low-ports 2>&1 || true)
if printf '%s\n' "$DLOW" | grep -q "apple-low-ports only applies to engine apple" \
  && ! printf '%s\n' "$DLOW" | grep -q "BOOTH_LOW_PORTS"; then
  pass 14 "--apple-low-ports on docker is ignored with a note"
else
  fail 14 "--apple-low-ports on docker is ignored with a note" "$DLOW"
fi

# 15. --public on apple without the flag warns that its proxy needs :80
# (the password prompt reads stdin, so give it one, as test040 does)
PUB=$(echo testpw | run_coding_booth --variant base --dryrun --engine apple --public --ok-public 2>&1 || true)
if printf '%s\n' "$PUB" | grep -q "Add --apple-low-ports"; then
  pass 15 "--public on apple without --apple-low-ports warns"
else
  fail 15 "--public on apple without --apple-low-ports warns" "$PUB"
fi

# 16-17. A project's booth wrapper is mounted read-only over the project. Apple
# container drops a folder's mount when a file directly in it is mounted too,
# which would empty /home/coder/code — so on apple the wrapper is mounted from a
# copy outside the project; docker mounts it from the project as before.
WRAP_PROJECT="$(mktemp -d)"
WRAP_CACHE="$(mktemp -d)"
printf '#!/bin/sh\n' > "$WRAP_PROJECT/booth"
WRAP=$(XDG_CACHE_HOME="$WRAP_CACHE" run_coding_booth --code "$WRAP_PROJECT" --variant base --dryrun --engine apple 2>/dev/null || true)
if printf '%s\n' "$WRAP" | grep -q -- "-v $WRAP_CACHE/codingbooth/apple-wrappers/[0-9a-f]*/booth:/home/coder/code/booth:ro" \
  && ! printf '%s\n' "$WRAP" | grep -q -- "-v $WRAP_PROJECT/booth:"; then
  pass 16 "apple mounts the booth wrapper from a copy outside the project"
else
  fail 16 "apple mounts the booth wrapper from a copy outside the project" "$WRAP"
fi
DWRAP=$(XDG_CACHE_HOME="$WRAP_CACHE" run_coding_booth --code "$WRAP_PROJECT" --variant base --dryrun --engine docker 2>/dev/null || true)
if printf '%s\n' "$DWRAP" | grep -q -- "-v $WRAP_PROJECT/booth:/home/coder/code/booth:ro"; then
  pass 17 "docker still mounts the booth wrapper from the project"
else
  fail 17 "docker still mounts the booth wrapper from the project" "$DWRAP"
fi
rm -rf "$WRAP_PROJECT" "$WRAP_CACHE"

# 18-23. --vm-memory / --vm-cpus / --vm-shm-size size the VM Apple container runs
# each booth in (1 GB / 4 CPUs by default); other engines ignore them.
VM=$(run_coding_booth --variant base --dryrun --engine apple --vm-memory 8g --vm-cpus 6 --vm-shm-size 2g 2>/dev/null || true)
if printf '%s\n' "$VM" | grep -q -- "--memory 8g" && printf '%s\n' "$VM" | grep -q -- "--cpus 6" \
  && printf '%s\n' "$VM" | grep -q -- "--shm-size 2g"; then
  pass 18 "apple: --vm-memory/--vm-cpus/--vm-shm-size become --memory/--cpus/--shm-size"
else
  fail 18 "apple: --vm-memory/--vm-cpus/--vm-shm-size become --memory/--cpus/--shm-size" "$VM"
fi

VMENV=$(CB_VM_MEMORY=6g run_coding_booth --variant base --dryrun --engine apple 2>/dev/null || true)
printf 'vm-cpus = "3"\n' > "$CONFIG"
VMCFG=$(run_coding_booth --config "$CONFIG" --variant base --dryrun --engine apple 2>/dev/null || true)
if printf '%s\n' "$VMENV" | grep -q -- "--memory 6g" && printf '%s\n' "$VMCFG" | grep -q -- "--cpus 3"; then
  pass 19 "CB_VM_MEMORY and vm-cpus in config.toml work too"
else
  fail 19 "CB_VM_MEMORY and vm-cpus in config.toml work too" "$VMENV"$'\n---\n'"$VMCFG"
fi

# a desktop gets 1g of /dev/shm; vm-shm-size replaces it rather than adding a second one
DSHM=$(run_coding_booth --variant kde --dryrun --engine apple --vm-memory 4g --vm-shm-size 2g 2>/dev/null || true)
if [[ "$(printf '%s\n' "$DSHM" | grep -c -- '--shm-size')" == "1" ]] && printf '%s\n' "$DSHM" | grep -q -- "--shm-size 2g"; then
  pass 20 "vm-shm-size replaces the desktop's 1g /dev/shm"
else
  fail 20 "vm-shm-size replaces the desktop's 1g /dev/shm" "$DSHM"
fi

DVM=$(run_coding_booth --variant base --dryrun --engine docker --vm-memory 8g 2>&1 || true)
if printf '%s\n' "$DVM" | grep -q "only apply to engine apple" && ! printf '%s\n' "$DVM" | grep -q -- "--memory"; then
  pass 21 "docker ignores --vm-memory, with a note"
else
  fail 21 "docker ignores --vm-memory, with a note" "$DVM"
fi

# A desktop on apple without --vm-memory: an image carrying the
# com.codingbooth.vm-memory-min label gets that memory; one without it (or not
# built yet, as under --dryrun on a fresh machine) gets a warning instead.
KDEWARN=$(run_coding_booth --variant kde --dryrun --engine apple 2>&1 || true)
if printf '%s\n' "$KDEWARN" | grep -q "Add --vm-memory 4g" \
  || { printf '%s\n' "$KDEWARN" | grep -q "Giving the booth's VM 4g" && printf '%s\n' "$KDEWARN" | grep -q -- "--memory 4g"; }; then
  pass 22 "a desktop on apple without --vm-memory gets the image's minimum, or a warning"
else
  fail 22 "a desktop on apple without --vm-memory gets the image's minimum, or a warning" "$KDEWARN"
fi

if ERR=$(run_coding_booth --variant base --dryrun --engine apple --vm-cpus lots 2>&1); then
  fail 23 "an invalid --vm-cpus is refused" "$ERR"
elif printf '%s\n' "$ERR" | grep -q 'invalid vm-cpus "lots"'; then
  pass 23 "an invalid --vm-cpus is refused"
else
  fail 23 "an invalid --vm-cpus is refused with a clear message" "$ERR"
fi
