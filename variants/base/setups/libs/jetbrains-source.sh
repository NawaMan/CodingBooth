# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Shared resolution for the JetBrains IDE scripts, so that jetbrains--setup.sh (which
# installs the IDE) and jetbrains-plugin--install.sh (which installs into it) agree on
# where plugins live, instead of each guessing.
#
# Everything comes out of the product-info.json every JetBrains IDE ships at its
# install root:
#
#   dataDirectoryName   IdeaIC2025.2    names the per-product config/plugin dirs
#   productCode         IC              first half of the marketplace build id
#   buildNumber         252.26830.84    second half
#
# ---- Why plugins go to /opt and not to $HOME ----
# A JetBrains IDE's default plugin dir is ~/.local/share/JetBrains/<dataDirectoryName>,
# and the container home is recreated per run — so a plugin installed there at build
# time is gone by the time anyone opens the IDE. Pointing idea.plugins.path at an
# image-level dir is what lets a plugin be baked in like any other tool. The property
# is spelled idea.* in every JetBrains IDE, not only IntelliJ IDEA.


JETBRAINS_PLUGINS_ROOT="${JETBRAINS_PLUGINS_ROOT:-/opt/jetbrains-plugins}"

# Where the IDEs themselves are unpacked. Overridable so the unit test can point the
# discovery at a fake tree; nothing in a real image sets it.
JETBRAINS_OPT_ROOT="${JETBRAINS_OPT_ROOT:-/opt}"


# jb_product_field <install-dir> <field>
#   Read one field out of the IDE's product-info.json.
jb_product_field() {
  jq -r --arg f "$2" '.[$f] // empty' "$1/product-info.json"
}


# jb_ides
#   Print "<ide-name><TAB><install-dir>" for every JetBrains IDE found under /opt.
#
#   Keyed off the <ide>-starter shim jetbrains--setup.sh writes into the install dir,
#   because that shim carries the IDE's own name (idea, pycharm, goland, ...) which
#   product-info.json does not. /opt/idea and /opt/idea-IC-2025.2.3 both match the
#   glob, so directories are deduped by their resolved path.
jb_ides() {
  local starter dir name seen=""

  for starter in "${JETBRAINS_OPT_ROOT}"/*/*-starter; do
    [ -x "$starter" ] || continue
    dir="$(cd "$(dirname "$starter")" && pwd -P)"
    [ -f "$dir/product-info.json" ] || continue

    case " ${seen} " in *" ${dir} "*) continue ;; esac
    seen="${seen} ${dir}"

    name="$(basename "$starter")"
    printf '%s\t%s\n' "${name%-starter}" "$dir"
  done
}


# jb_plugins_dir <install-dir>
#   Where this IDE's custom plugins live. An idea.plugins.path already in
#   bin/idea.properties wins — an image may have been built before this lib existed,
#   or an operator may have pointed it somewhere else on purpose.
jb_plugins_dir() {
  local dir="$1"
  local prop="${dir}/bin/idea.properties"
  local configured=""

  # sed rather than grep|cut: callers run under `set -o pipefail`, where a grep that
  # matches nothing — the normal case, the first time — would fail the assignment.
  if [ -f "$prop" ]; then
    configured="$(sed -n 's/^idea\.plugins\.path=//p' "$prop" | tail -n 1)"
  fi

  if [ -n "$configured" ]; then
    printf '%s\n' "$configured"
    return 0
  fi

  printf '%s/%s\n' "$JETBRAINS_PLUGINS_ROOT" "$(jb_product_field "$dir" dataDirectoryName)"
}


# jb_build_id <install-dir>
#   The build the marketplace wants when asked whether a plugin fits: IC-252.26830.84.
jb_build_id() {
  printf '%s-%s\n' "$(jb_product_field "$1" productCode)" "$(jb_product_field "$1" buildNumber)"
}


# jb_relax_perms <dir>
#   Build-time root owns everything it writes; the runtime user (coder) must still be
#   able to install and update plugins from the IDE's own marketplace UI.
jb_relax_perms() {
  chmod -R a+rX "$1"
  find "$1" -type d -exec chmod a+w {} +
}


# jb_ensure_plugins_path <install-dir>
#   Create the image-level plugin dir and point the IDE at it. Idempotent: an
#   idea.plugins.path already in the file is left alone. Prints the dir.
jb_ensure_plugins_path() {
  local dir="$1"
  local prop="${dir}/bin/idea.properties"
  local plugins

  plugins="$(jb_plugins_dir "$dir")"
  mkdir -p "$plugins"

  if [ -f "$prop" ] && ! grep -qE '^idea\.plugins\.path=' "$prop"; then
    printf 'idea.plugins.path=%s\n' "$plugins" >> "$prop"
  fi

  jb_relax_perms "$plugins"
  printf '%s\n' "$plugins"
}


# jb_resolve_id <id>
#   Turn whichever id form the user had to hand into the xmlId the marketplace and
#   `installPlugins` both want. A plugin page carries two: the xmlId ("Lombook Plugin")
#   and the number in its URL (6317). `installPlugins 6317` answers "unknown plugins",
#   so the number is looked up here rather than handed on.
jb_resolve_id() {
  local id="$1" xml

  case "$id" in
    ''|*[!0-9]*) printf '%s\n' "$id"; return 0 ;;
  esac

  xml="$(curl -fsSL "https://plugins.jetbrains.com/api/plugins/${id}" 2>/dev/null | jq -r '.xmlId // empty')"
  [ -n "$xml" ] || return 1

  printf '%s\n' "$xml"
}
