#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Keep a locally-built variant image in sync with the source tree before tests
# run against it, instead of leaving that to memory.
#
# `docker build`'s own layer cache already knows, exactly, whether anything a
# Dockerfile COPYs has changed since the image was last built — that is what
# cache invalidation IS. So "is this image stale" does not need a second,
# hand-rolled answer (a git SHA baked as a label, a content hash we maintain
# ourselves, a list of paths to watch that can itself drift from the real
# Dockerfile...): it needs the real build run again. When nothing changed,
# BuildKit hits cache top-to-bottom and this returns in about a second, even
# for the ~5GB desktop images (measured on 2026-09-28: base 2.2s, desktop-kde
# 0.7s). When something did change, it rebuilds exactly the changed layers and
# whatever depends on them, and the tag now IS fresh — the check and the fix
# are the same command, so there is nothing to keep in sync by hand.
#
# This is what caught, as stale local images rather than "flaky" tests, three
# real problems in one session: the Console UI's i3 tiling landing after the
# local base image was last built, a new LaTeX setup script not yet baked in,
# and a version bump the local image hadn't picked up.
#
# What this does NOT cover: an example's own `env APT_SNAPSHOT=` pin going
# stale relative to a freshly-rebuilt base image's archive snapshot — a
# per-example config value, bumped at release (release-push skill, "Apt snapshot
# pin"). If it does fail, apt--install.sh names the cause and the fix.
#
# CB_NO_IMAGE_REFRESH=1 skips this — e.g. deliberately testing against an
# older pinned image, or no Docker/network access at all.
# -----------------------------------------------------------------------------

_efi_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# _efi_image_id <variant> <version>: the image's content-addressed ID, or
# empty if the tag does not exist locally yet (first build).
_efi_image_id() {
  docker image inspect "nawaman/codingbooth:${1}-${2}" --format '{{.Id}}' 2>/dev/null || true
}

# ensure_fresh_image <variant> [<variant> ...]
# Rebuilds each named variant locally — a cheap no-op when nothing relevant
# changed. Prints one line per variant, but only when a rebuild actually
# happened (image ID changed); silent when the tag was already fresh, which
# is the common case and should not add noise ahead of every suite/example
# run. Returns non-zero and prints the build's own output when a rebuild
# genuinely fails (only then — a cache hit never fails).
ensure_fresh_image() {
  [[ "${CB_NO_IMAGE_REFRESH:-}" == "1" ]] && return 0
  [[ $# -eq 0 ]] && return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0

  local repo_root
  repo_root="$(_efi_repo_root)"
  [[ -x "${repo_root}/build/docker-build.sh" ]] || return 0

  local version
  version="$(tr -d ' \t\n\r' < "${repo_root}/version.txt" 2>/dev/null)"
  [[ -n "$version" ]] || return 0

  local variant before after out rc start elapsed
  for variant in "$@"; do
    before="$(_efi_image_id "$variant" "$version")"

    start=$(date +%s)
    out="$(cd "$repo_root" && ./build/docker-build.sh "$variant" 2>&1)"
    rc=$?
    elapsed=$(( $(date +%s) - start ))

    if [[ $rc -ne 0 ]]; then
      echo "❌ ensure_fresh_image: rebuilding '${variant}' failed:" >&2
      echo "$out" | sed 's/^/    /' >&2
      return 1
    fi

    after="$(_efi_image_id "$variant" "$version")"
    if [[ -z "$before" ]]; then
      echo "🔨 ${variant}-${version} had no local image — built one (${elapsed}s)"
    elif [[ "$before" != "$after" ]]; then
      echo "🔄 ${variant}-${version} was stale — rebuilt in ${elapsed}s"
    fi
  done
  return 0
}

# example_image_variant <example-dir>: the canonical image-variant name
# (base|notebook|codeserver|desktop-xfce|desktop-kde|desktop-lxqt|desktop-wayland)
# an example's .booth/config.toml resolves to, applying the same aliases as
# ValidateVariant in cli/src/pkg/booth/validate_variant.go (xfce -> desktop-xfce,
# ide -> codeserver, terminal -> base, absent -> base, ...). Kept in sync with
# that switch by hand; if a variant alias is ever added there, add it here too.
example_image_variant() {
  local cfg="$1/.booth/config.toml" v="base" raw
  if [[ -f "$cfg" ]]; then
    raw="$(grep -m1 '^variant[[:space:]]*=' "$cfg" 2>/dev/null | sed -E 's/^variant[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
    [[ -n "$raw" ]] && v="$raw"
  fi
  case "$v" in
    base|notebook|codeserver|desktop-xfce|desktop-kde|desktop-lxqt|desktop-wayland) ;;
    default|console|terminal) v="base" ;;
    ide) v="codeserver" ;;
    desktop) v="desktop-xfce" ;;
    xfce|kde|lxqt|wayland) v="desktop-$v" ;;
    *) v="base" ;; # unrecognized: fall back rather than fail the preflight over it
  esac
  echo "$v"
}
