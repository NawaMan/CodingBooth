#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Registers every JDK in the image as an SDK in the JetBrains IDEs, so a Java project
# opens with a working compiler instead of an unresolved project SDK.
#
# Usage: jetbrains-jdk--setup.sh
#
# A JetBrains IDE finds JDKs only in a handful of well-known places -- and one of them is
# JAVA_HOME, which a booth does set. Measured on IDEA IC 2025.2.3: a booth with a single
# JDK gets it auto-detected, named `temurin-25`, and a Maven project resolves without any
# of this. So this is NOT a fix for a broken IDE; what it adds is:
#
#   - **Every** JDK, not just one. Auto-detection finds what JAVA_HOME points at;
#     all-java-example installs six, and the other five stay invisible.
#   - A table that does not depend on JAVA_HOME being aimed at the right JDK, nor on the
#     IDE's naming convention continuing to match what projects ask for.
#
# ---- Why the seed, and not the image ----
# Unlike plugins (see jetbrains-plugin--install.sh, which puts them in /opt), the SDK
# table is per-user config: ~/.config/JetBrains/<dataDirectoryName>/options/jdk.table.xml.
# The container home is recreated per run, so it is written to /etc/cb-home-seed instead,
# which booth-entry copies into the home at start -- no-clobber, so a user who edits
# their SDK list keeps their version from then on.
#
# ---- Why the names matter ----
# SDKs are named <vendor>-<major> (temurin-25, corretto-17), which is what a JetBrains
# IDE calls a JDK it discovers by itself. Projects reference SDKs by name in
# .idea/misc.xml, so matching that convention is what makes an existing project resolve
# without editing it -- examples/workspaces/java-example already asks for "temurin-25".
# The JDKs are also symlinked into the seed's ~/.jdks, one of the dirs the IDE scans, so
# its own detection agrees with this table rather than adding a duplicate entry.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0"
        echo "Registers every JDK under /opt/jdk-installs as an SDK in each JetBrains IDE."
        exit 0
        ;;
esac

# This script always runs as root during the build.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-${SCRIPT_DIR}/libs}

source "${SETUP_LIBS_DIR}/skip-setup.sh"
source "${SETUP_LIBS_DIR}/jetbrains-source.sh"

JDK_INSTALLS_DIR="${JDK_INSTALLS_DIR:-/opt/jdk-installs}"
HOME_SEED_DIR="${HOME_SEED_DIR:-/etc/cb-home-seed}"

# Either half missing is a skip, not an error: `setup idea` on an image with no Java is
# a perfectly good Kotlin or Scala booth, and `setup jdk` without an IDE is the common
# case on every non-desktop variant.
if ! "${SCRIPT_DIR}/cb-has-jetbrains.sh"; then
    skip_setup "$SCRIPT_NAME" "no JetBrains IDE installed"
fi

JDK_HOMES=()
for jdk in "${JDK_INSTALLS_DIR}"/*; do
    [ -x "${jdk}/bin/java" ] || continue
    JDK_HOMES+=("$jdk")
done

if [ ${#JDK_HOMES[@]} -eq 0 ]; then
    skip_setup "$SCRIPT_NAME" "no JDK under ${JDK_INSTALLS_DIR}"
fi

# release_field <jdk-home> <key>
#   Values in a JDK's release file are quoted; strip them.
release_field() {
    sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$1/release" 2>/dev/null | head -n 1
}

# sdk_name <jdk-home>
#   <vendor>-<major>, taken from the install dir name jdk--setup.sh chose
#   (<version>-<vendor>). The release file names the implementor ("Eclipse Adoptium"),
#   not the vendor token the rest of the catalog uses ("temurin"), so the dir wins.
sdk_name() {
    local base version vendor
    base="$(basename "$1")"
    version="${base%%-*}"
    vendor="${base#*-}"
    printf '%s-%s\n' "$vendor" "${version%%.*}"
}

# sdk_roots <jdk-home> <kind>
#   The <root> entries for one SDK. Java 9+ exposes its classes through the module
#   image (jrt://) and its sources as per-module entries inside src.zip. Java 8 has
#   neither: classes are jars under jre/lib, sources a flat src.zip. The IDE can
#   re-derive roots at runtime — its own auto-detected entry is written with none at
#   all — so this is about handing it a table that is correct for the JDK it names,
#   not about resolution failing outright without one.
sdk_roots() {
    local jdk="$1" kind="$2" modules m jar

    modules="$("$jdk/bin/java" --list-modules 2>/dev/null | sed 's/@.*//')" || modules=""

    if [ -n "$modules" ]; then
        for m in $modules; do
            case "$kind" in
                class)  printf '            <root type="simple" url="jrt://%s!/%s" />\n' "$jdk" "$m" ;;
                source) [ -f "$jdk/lib/src.zip" ] &&
                        printf '            <root type="simple" url="jar://%s/lib/src.zip!/%s" />\n' "$jdk" "$m" ;;
            esac
        done
        return 0
    fi

    # --- Java 8 and earlier ---
    case "$kind" in
        class)
            for jar in "$jdk"/jre/lib/*.jar "$jdk"/jre/lib/ext/*.jar; do
                [ -f "$jar" ] || continue
                printf '            <root type="simple" url="jar://%s!/" />\n' "$jar"
            done
            ;;
        source)
            [ -f "$jdk/src.zip" ] &&
                printf '            <root type="simple" url="jar://%s/src.zip!/" />\n' "$jdk"
            ;;
    esac
}

# ---- The SDK table, shared by every IDE in the image ----
TABLE="$(mktemp)"
trap 'rm -f "$TABLE"' EXIT

{
    echo '<application>'
    echo '  <component name="ProjectJdkTable">'
    for jdk in "${JDK_HOMES[@]}"; do
        name="$(sdk_name "$jdk")"
        java_version="$(release_field "$jdk" JAVA_VERSION)"
        echo '    <jdk version="2">'
        printf '      <name value="%s" />\n' "$name"
        echo '      <type value="JavaSDK" />'
        printf '      <version value="java version &quot;%s&quot;" />\n' "${java_version:-unknown}"
        printf '      <homePath value="%s" />\n' "$jdk"
        echo '      <roots>'
        # IDEA 2025.2 ships no jdkAnnotations.jar to point at; an empty composite is
        # what it writes itself in that case.
        echo '        <annotationsPath><root type="composite" /></annotationsPath>'
        echo '        <classPath>'
        echo '          <root type="composite">'
        sdk_roots "$jdk" class
        echo '          </root>'
        echo '        </classPath>'
        echo '        <javadocPath><root type="composite" /></javadocPath>'
        echo '        <sourcePath>'
        echo '          <root type="composite">'
        sdk_roots "$jdk" source
        echo '          </root>'
        echo '        </sourcePath>'
        echo '      </roots>'
        echo '      <additional />'
        echo '    </jdk>'
        echo "• ${name} → ${jdk}" >&2
    done
    echo '  </component>'
    echo '</application>'
} > "$TABLE"

# ---- Seed it for every JetBrains IDE in the image ----
IDE_COUNT=0
while IFS="$(printf '\t')" read -r ide dir; do
    [ -n "$ide" ] || continue
    data="$(jb_product_field "$dir" dataDirectoryName)"
    [ -n "$data" ] || continue

    options="${HOME_SEED_DIR}/.config/JetBrains/${data}/options"
    mkdir -p "$options"
    cp "$TABLE" "${options}/jdk.table.xml"
    chmod 0644 "${options}/jdk.table.xml"
    echo "🧩 ${ide}: seeded ${options}/jdk.table.xml"
    IDE_COUNT=$((IDE_COUNT + 1))
done < <(jb_ides)

# ---- And where the IDE looks on its own ----
# ~/.jdks is one of the dirs a JetBrains IDE scans for JDKs. Linking the same homes
# there means its own detection recognises what the table already declares, instead of
# offering to add a second entry for the same JDK.
mkdir -p "${HOME_SEED_DIR}/.jdks"
for jdk in "${JDK_HOMES[@]}"; do
    ln -sfn "$jdk" "${HOME_SEED_DIR}/.jdks/$(sdk_name "$jdk")"
done

echo "✅ Registered ${#JDK_HOMES[@]} JDK(s) with ${IDE_COUNT} JetBrains IDE(s)."
echo "ℹ️  Ready to use:"
cat <<EOF
  The SDKs are named <vendor>-<major> — temurin-25, corretto-17 — which is what a
  project's .idea/misc.xml refers to:

      <component name="ProjectRootManager" project-jdk-name="$(sdk_name "${JDK_HOMES[0]}")" project-jdk-type="JavaSDK" />

  Change the SDK list from the IDE (File → Project Structure → SDKs) and your edit
  sticks: the seed is copied into the home no-clobber, so it never overwrites yours.
EOF
