#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Answers the JetBrains IDE prompts that otherwise block a fresh booth's first launch,
# by seeding the files the IDE writes when you answer them by hand.
#
# Usage: jetbrains-first-run--setup.sh [<trusted-path>]
#   <trusted-path>  project path to trust; default $USER_HOME$/code (the workspace mount).
#                   $USER_HOME$ is the IDE's own macro and is expanded by the IDE.
#
# Opening a JetBrains IDE in a fresh container means clicking through up to four modals
# over noVNC before anything is usable, and the container home is recreated per run, so
# it is every start rather than once. This answers three of them:
#
#   Third-Party Plugins Notice  <config>/options/updates.xml
#                               UpdatesConfigurable/THIRD_PARTY_PLUGINS_ALLOWED
#   Trust and Open Project      <config>/options/trusted-paths.xml
#                               Trusted.Paths/TRUSTED_PROJECT_PATHS
#   Data Sharing                ~/.local/share/JetBrains/consentOptions/accepted
#                               "<id>:<version>:<0|1>:<epoch-ms>"  -- 0, i.e. declined
#
# ---- What it deliberately does NOT answer ----
# The **User Agreement**. Accepting a licence on someone's behalf at image-build time is
# a legal act, not a configuration default, so the EULA dialog still appears on first
# launch and a human still clicks it. (For the record, it is stored as
# `euacommunity_accepted_version` in a Java Preferences node whose name is character-
# encoded -- not a file anyone should hand-write.)
#
# ---- Why these values are measured, not derived ----
# Every one of them was read back out of an IDE that had been clicked through by hand,
# because guessing them does not work: an earlier attempt put the EULA key in
# `~/.java/.userPrefs/jetbrains/privacy_policy/` with version `2.1`, and the real record
# is version `1.0` in an encoded node. If a future IDE release stops honouring one of
# these, re-measure the same way -- diff the config tree across a clean exit.
#
# ---- Trust is scoped, on purpose ----
# Only the workspace path is trusted, never "trust all projects in this folder": the
# prompt exists to stop untrusted project code from executing, and the booth's own
# project is the only thing its author vouched for.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [<trusted-path>]"
        echo "Seeds the answers to the JetBrains first-launch prompts (not the EULA)."
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

TRUSTED_PATH="${1:-\$USER_HOME\$/code}"
HOME_SEED_DIR="${HOME_SEED_DIR:-/etc/cb-home-seed}"

if ! "${SCRIPT_DIR}/cb-has-jetbrains.sh"; then
    skip_setup "$SCRIPT_NAME" "no JetBrains IDE installed"
fi

IDE_COUNT=0
while IFS="$(printf '\t')" read -r ide dir; do
    [ -n "$ide" ] || continue
    data="$(jb_product_field "$dir" dataDirectoryName)"
    [ -n "$data" ] || continue

    options="${HOME_SEED_DIR}/.config/JetBrains/${data}/options"
    mkdir -p "$options"

    # --- Third-Party Plugins Notice ---
    # Raised for every plugin whose vendor is not JetBrains. Whoever wrote
    # `install jetbrains-plugin <id>` already chose those plugins deliberately, at build
    # time; the modal asks the person opening the IDE to re-affirm a decision they may
    # not have made and cannot evaluate from a dialog.
    cat > "${options}/updates.xml" <<'EOF'
<application>
  <component name="UpdatesConfigurable">
    <option name="THIRD_PARTY_PLUGINS_ALLOWED" value="true" />
  </component>
</application>
EOF

    # --- Trust and Open Project ---
    cat > "${options}/trusted-paths.xml" <<EOF
<application>
  <component name="Trusted.Paths">
    <option name="TRUSTED_PROJECT_PATHS">
      <map>
        <entry key="${TRUSTED_PATH}" value="true" />
      </map>
    </option>
  </component>
</application>
EOF

    chmod 0644 "${options}/updates.xml" "${options}/trusted-paths.xml"
    echo "🧩 ${ide}: seeded third-party-plugins + trusted-paths under ${options}"
    IDE_COUNT=$((IDE_COUNT + 1))
done < <(jb_ides)

# --- Data Sharing ---
# Product-independent: one file for every JetBrains IDE on the machine, which is why it
# is written once rather than per IDE. The third field is the answer, and 0 means "Don't
# Send" -- declining is the defensible default to make on someone else's behalf, since
# the alternative ships their usage statistics without them choosing to.
CONSENT_DIR="${HOME_SEED_DIR}/.local/share/JetBrains/consentOptions"
mkdir -p "$CONSENT_DIR"

# The fourth field is a millisecond timestamp. %3N is a GNU date extension: BSD
# date does not implement %N and copies the letter through, so `date +%s%3N`
# yields "1787331798N" there and JetBrains is handed a field it cannot parse.
# Booths run GNU coreutils, so the fast path is the normal one; the fallback
# keeps the file well-formed anywhere else, at whole-second resolution.
CONSENT_STAMP="$(date +%s%3N 2>/dev/null || true)"
if ! [[ "$CONSENT_STAMP" =~ ^[0-9]+$ ]]; then
    CONSENT_STAMP="$(date +%s)000"
fi
printf 'rsch.send.usage.stat:1.1:0:%s' "$CONSENT_STAMP" > "${CONSENT_DIR}/accepted"
chmod 0644 "${CONSENT_DIR}/accepted"
echo "🧩 data sharing: declined (rsch.send.usage.stat)"

echo "✅ Seeded first-launch answers for ${IDE_COUNT} JetBrains IDE(s)."
echo "ℹ️  Ready to use:"
cat <<EOF
  Still shown on first launch: the JetBrains User Agreement. Accepting a licence for
  you is not something a build step should do, so that one dialog remains yours.

  Trusted project path: ${TRUSTED_PATH}
  Data sharing:         declined — turn it on in Settings → Appearance & Behavior →
                        System Settings → Data Sharing if you want to send statistics.

  These are seeded, so they are copied into the home no-clobber: change any of them in
  the IDE and your version survives every restart.
EOF
