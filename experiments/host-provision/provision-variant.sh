#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# provision-variant.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Replays a non-base variant's Dockerfile on the machine itself, after
# base-provision.sh has done the base one. The variant Dockerfiles use only:
#   ARG K=V   -> substituted into later lines (an exported K wins, like --build-arg)
#   RUN cmd   -> cmd                (root, login shell, like the Dockerfile's SHELL)
#   FROM/LABEL/CMD -> skipped, logged (CMD is the variant's start command)
# cleanup-after--setup.sh is skipped: it wipes /tmp, /var/tmp and /root/.cache,
# an image-size step that is harmful on a live machine (base-provision.sh too).
# Every line is attempted; a failing one is recorded and the next one runs.
#
# Usage: sudo CB_TARGET=host REPORT=file provision-variant.sh <kit-root> <variant>
# -----------------------------------------------------------------------------

set -uo pipefail

KIT="${1:?usage: provision-variant.sh <kit-root> <variant>}"
VARIANT="${2:?usage: provision-variant.sh <kit-root> <variant>}"
DOCKERFILE="$KIT/variants/$VARIANT/Dockerfile"
REPORT="${REPORT:-$HOME/host-provision-report.txt}"
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }
[ -f "$DOCKERFILE" ] || { echo "❌ No Dockerfile for variant '$VARIANT': $DOCKERFILE" >&2; exit 1; }

export PATH="/opt/codingbooth/setups:$PATH"
export DEBIAN_FRONTEND=noninteractive
declare -A ARGS=()

record() { printf '%-5s %s\n' "$1" "$2" | tee -a "$REPORT"; }

subst_args() {
  local s="$1" k
  for k in "${!ARGS[@]}"; do
    s="${s//\$\{$k\}/${ARGS[$k]}}"
  done
  printf '%s' "$s"
}

run_line() {
  local label="$1" cmd="$2" log
  log="$(mktemp)"
  printf '\n[provision-variant] --- %s\n' "$cmd"
  if bash -lc "$cmd" < /dev/null 2>&1 | tee "$log"; then
    if grep -q '^SKIP: ' "$log"; then
      record SKIP "$label  ($(grep -m1 '^SKIP: ' "$log" | cut -c7-120))"
    else
      record PASS "$label"
    fi
  else
    record FAIL "$label  (last line: $(grep -v '^\s*$' "$log" | tail -n 1 | cut -c1-120))"
  fi
  rm -f "$log"
}

echo "== variant $VARIANT (CB_TARGET=${CB_TARGET:-?})" | tee -a "$REPORT"

# Join continuation lines first, so each directive is one line.
while IFS= read -r line || [ -n "$line" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac
  cmd="${line%% *}"
  rest="${line#"$cmd"}"; rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$cmd" in
    ARG)
      key="${rest%%=*}"
      if [ -n "${!key+x}" ]; then ARGS["$key"]="${!key}"
      elif [[ "$rest" == *=* ]]; then ARGS["$key"]="${rest#*=}"
      else ARGS["$key"]=""
      fi
      ;;
    RUN)
      expanded="$(subst_args "$rest")"
      case "$expanded" in
        *cleanup-after--setup.sh*)
          record SKIP "RUN ${expanded:0:80}  (wipes /tmp and caches: an image-size step)" ;;
        *)
          run_line "variant $VARIANT: ${expanded:0:100}" "$expanded" ;;
      esac
      ;;
    CMD)
      record SKIP "CMD $rest  (the variant's start command; not started by prepare)"
      ;;
    FROM|LABEL)
      ;;
    *)
      record SKIP "$cmd ${rest:0:80}  (not replayed)"
      ;;
  esac
done < <(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$DOCKERFILE")
