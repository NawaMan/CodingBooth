#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs arbitrary JetBrains IDE plugins by marketplace id, at build
# time, into every JetBrains IDE the image has.
#
# It is the escape hatch beside `setup jetbrains-plugin`, which names one IDE and one
# plugin and re-runs the install at every container start. This one takes whatever you
# name, bakes it into the image, and needs no network once the image is built.
#
# Usage: jetbrains-plugin--install.sh <id>[@<version>] [more...]
# Example: jetbrains-plugin--install.sh IdeaVIM
#          jetbrains-plugin--install.sh 6317 izhangzhihao.rainbow.brackets
#          jetbrains-plugin--install.sh IdeaVIM@2.31.0
#
# Ids resolve against the JetBrains Marketplace (https://plugins.jetbrains.com). Both
# id forms a plugin page carries are accepted: the xmlId ("Lombook Plugin", "IdeaVIM",
# "izhangzhihao.rainbow.brackets") and the number in the page URL (6317), which is
# looked up and turned into the xmlId. Reach for the number when the xmlId contains a
# space -- ids here are split on whitespace, and Lombok's xmlId really is the
# two-word, misspelled "Lombook Plugin".
#
# Reproducibility: a trailing @version pins the plugin to that release. Unpinned ids
# go through the IDE's own `installPlugins` command, which picks the newest build
# compatible with this IDE and pulls in the plugins it depends on; a pinned id is
# fetched straight from the marketplace, which pins exactly but resolves nothing --
# a pinned plugin with dependencies needs those named too. See docs/REPRODUCIBILITY.md.
#
# A plugin is not expected to exist for every IDE in the image: org.jetbrains.plugins.go
# has no build for IntelliJ IDEA Community, and asking for it there is a 404 rather than
# a mistake. So an id that lands in at least one IDE is a success, and an id that lands
# in none is a hard error -- you named it explicitly, and a silent no-op would hand you
# an image missing the plugin you asked for.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <id>[@<version>] [more...]"
        echo "Example: $0 IdeaVIM"
        echo "         $0 6317 izhangzhihao.rainbow.brackets"
        echo "         $0 IdeaVIM@2.31.0"
        exit 0
        ;;
esac

# This script always runs as root during the build.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# Expand comma-separated ids into separate arguments -- without re-splitting an id that
# already arrived as one argument.
#
# Through a Boothfile only the comma form can reach here: `install jetbrains-plugin
# ${JETBRAINS_PLUGIN_PKGS}` expands unquoted, so the shell has already split on
# whitespace by the time this runs. But a curated setup calling this script directly can
# hand over `"Lombook Plugin"` as a single argument, and word-splitting that would turn
# one valid id into two invalid ones.
_ids=()
for _arg in "$@"; do
    while IFS= read -r _id; do
        [ -n "$_id" ] && _ids+=("$_id")
    done < <(printf '%s\n' "$_arg" | tr ',' '\n')
done
set -- ${_ids[@]+"${_ids[@]}"}

# No ids requested is a no-op, not an error: the jetbrains-plugin-pkg template emits
# `install jetbrains-plugin ${JETBRAINS_PLUGIN_PKGS}` with the list defaulting to
# empty, so failing here would break the image build of every project that selects it
# without naming ids. Naming nothing is not the same as naming something broken -- an
# unresolvable id is still the hard error described above.
if [ $# -eq 0 ]; then
    echo "ℹ️  No plugin ids requested; nothing to install."
    exit 0
fi

# Sourced after the no-op exit, so an unnamed-plugins build needs none of this.
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-${SCRIPT_DIR}/libs}
source "${SETUP_LIBS_DIR}/skip-setup.sh"
# Reuse the plugin-dir / build-id resolution jetbrains--setup.sh uses, so the dir this
# installs into is the dir the IDE was pointed at.
source "${SETUP_LIBS_DIR}/jetbrains-source.sh"

# Unlike code-extension--install.sh, a missing host is a skip rather than an error
# here. The JetBrains IDEs are desktop-only: jetbrains--setup.sh itself calls
# skip_setup on a non-desktop variant, so `setup idea` + `install jetbrains-plugin X`
# on the base variant leaves no IDE to install into through no fault of the ids.
if ! "${SCRIPT_DIR}/cb-has-jetbrains.sh"; then
    skip_setup "$SCRIPT_NAME" "no JetBrains IDE installed"
fi

# ---- Collect the IDEs once ----
IDE_NAMES=()
IDE_DIRS=()
while IFS="$(printf '\t')" read -r ide dir; do
    [ -n "$ide" ] || continue
    IDE_NAMES+=("$ide")
    IDE_DIRS+=("$dir")
done < <(jb_ides)

if [ ${#IDE_DIRS[@]} -eq 0 ]; then
    skip_setup "$SCRIPT_NAME" "no JetBrains IDE install dir under /opt"
fi

echo "🧩 JetBrains IDEs found: ${IDE_NAMES[*]}"

FAILED=()

# install_pinned <plugins-dir> <build-id> <xml-id> <version>
#   `installPlugins` has no version argument, so a pin is fetched from the marketplace
#   directly. Unzipped to a staging dir first: the endpoint answers 200 with an HTML
#   error page for some bad combinations, and a half-extracted plugin dir is worse
#   than none.
install_pinned() {
    local plugins_dir="$1" build_id="$2" xml_id="$3" version="$4"
    local url stage rc=0

    # Spaces are the only character real xmlIds carry that a URL will not take as-is.
    url="https://plugins.jetbrains.com/pluginManager?action=download&id=${xml_id// /+}"
    url="${url}&build=${build_id}&version=${version}"

    stage="$(mktemp -d)"
    if ! curl -fsSL -o "${stage}/plugin.zip" "$url"; then
        rm -rf "$stage"
        return 1
    fi

    if ! unzip -q -o "${stage}/plugin.zip" -d "${stage}/x"; then
        rm -rf "$stage"
        return 1
    fi

    # A plugin archive unpacks to a single top-level dir holding lib/ or META-INF/.
    if ! find "${stage}/x" -mindepth 2 -maxdepth 3 \
            \( -name 'plugin.xml' -o -type d -name 'lib' \) | grep -q .; then
        echo "  ❌ downloaded archive does not look like a plugin: ${xml_id}@${version}" >&2
        rm -rf "$stage"
        return 1
    fi

    mkdir -p "$plugins_dir"
    cp -a "${stage}/x/." "${plugins_dir}/" || rc=1
    rm -rf "$stage"
    return $rc
}

# install_latest <starter> <xml-id>
#   The IDE's own installer: resolves the newest compatible build and any plugins this
#   one depends on, exits 1 on an id it cannot find, and reports "already installed" on
#   a repeat. It refuses to run while an instance of that IDE is up -- never the case
#   during an image build, but the reason this is not something to run at container
#   start.
install_latest() {
    local starter="$1" xml_id="$2"
    "$starter" installPlugins "$xml_id"
}

for spec in "$@"; do
    [ -n "$spec" ] || continue

    case "$spec" in
        *@*) raw_id="${spec%@*}"; version="${spec##*@}" ;;
        *)   raw_id="$spec";      version=""            ;;
    esac

    if ! xml_id="$(jb_resolve_id "$raw_id")"; then
        echo "  ❌ ${spec}: no plugin with numeric id ${raw_id} on the marketplace" >&2
        FAILED+=("$spec")
        continue
    fi
    if [ "$xml_id" != "$raw_id" ]; then
        echo "  ↪ ${raw_id} → ${xml_id}"
    fi

    landed=0
    for i in "${!IDE_DIRS[@]}"; do
        ide="${IDE_NAMES[$i]}"
        dir="${IDE_DIRS[$i]}"
        plugins_dir="$(jb_ensure_plugins_path "$dir")"

        if [ -n "$version" ]; then
            if install_pinned "$plugins_dir" "$(jb_build_id "$dir")" "$xml_id" "$version"; then
                echo "  ✔ ${xml_id}@${version} → ${ide}"
                landed=$((landed + 1))
            else
                echo "  ⚠ ${xml_id}@${version} not available for ${ide} ($(jb_build_id "$dir"))" >&2
            fi
        else
            if install_latest "${dir}/${ide}-starter" "$xml_id"; then
                echo "  ✔ ${xml_id} → ${ide}"
                landed=$((landed + 1))
            else
                echo "  ⚠ ${xml_id} not available for ${ide} ($(jb_build_id "$dir"))" >&2
            fi
        fi

        jb_relax_perms "$plugins_dir"
    done

    if [ "$landed" -eq 0 ]; then
        FAILED+=("$spec")
    fi
done

# `installPlugins` boots the IDE headless, which leaves a config/cache tree behind
# under build-time root's home. It is dead weight in the image and is not what the
# runtime user reads.
# Best-effort: tidying is not worth failing an otherwise good install over.
rm -rf "${HOME}/.cache/JetBrains" "${HOME}/.local/share/JetBrains" "${HOME}/.config/JetBrains" 2>/dev/null || true

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "" >&2
    echo "❌ ${#FAILED[@]} plugin(s) installed into no IDE:" >&2
    for f in "${FAILED[@]}"; do echo "   - ${f}" >&2; done
    echo "" >&2
    echo "   Check the id at https://plugins.jetbrains.com — the xmlId is on the" >&2
    echo "   plugin's page under 'Additional Information', and the numeric id is in" >&2
    echo "   its URL. A plugin also has to publish a build for the IDE in this image" >&2
    echo "   (${IDE_NAMES[*]}); many are IntelliJ IDEA Ultimate only." >&2
    exit 1
fi

echo "✅ JetBrains plugin installation completed."
