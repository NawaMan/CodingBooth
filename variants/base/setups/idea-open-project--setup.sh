#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Usage in Boothfile:  setup idea-open-project [DEFAULT|GENERAL|MAVEN|GRADLE]
#
# Unlike Eclipse, IntelliJ has no separate "workspace" to register a project into --
# a folder with a valid .idea/ is a complete, self-contained project, and opening it
# (via GUI or `idea <path>`) just works, no import wizard. Confirmed live: after
# .idea/ existed, no further prompts appeared.
#
# What's missing is just getting there without clicking through:
#   1. .idea/ has to exist. If it doesn't, IntelliJ's own "Open" wizard asks the user
#      to pick a build system (Gradle vs. the Eclipse project files this same repo
#      already carries) -- fine once, annoying every fresh workspace. Gradle's own
#      `idea` plugin (already applied in this project's build.gradle) generates the
#      same .idea/ files headlessly, so we run that instead of guessing at IntelliJ's
#      project-descriptor format the way the Eclipse fix had to.
#   2. IntelliJ's "recent projects" list is not a file we can safely hand-write on a
#      modern IDE -- newer versions moved it into an internal app-internal-state.db /
#      "Station" service, not the old options/recentProjects.xml. So instead of trying
#      to make a bare `idea` launch remember the project, we patch the IDE's own
#      starter script to default to opening the project directory when launched with
#      no arguments -- both the CLI shim and the desktop icon funnel through it.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"

LEVEL=73
KIND="${1:-DEFAULT}"
IDEA_DIR="$(readlink -f /opt/idea 2>/dev/null || true)"

if [ -z "$IDEA_DIR" ] || [ ! -d "$IDEA_DIR/bin" ]; then
  skip_setup "$SCRIPT_NAME" "IntelliJ IDEA not installed (select 'idea' before 'idea-open-project')"
fi

STARTER_FILE="${IDEA_DIR}/idea-starter"
if [ ! -f "$STARTER_FILE" ]; then
  skip_setup "$SCRIPT_NAME" "starter script not found at ${STARTER_FILE}"
fi

# --- Patch the starter: default to opening the project when launched bare ---
# Both /usr/local/bin/idea (the CLI shim) and the .desktop Exec line just forward
# their args to this starter, so patching it here covers both launch paths.
cat > "$STARTER_FILE" <<'STARTEREOF'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f /etc/profile.d/60-cb-jdk--profile.sh    ] && source /etc/profile.d/60-cb-jdk--profile.sh    2>/dev/null || true
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
if [ "$#" -eq 0 ] && [ -d "${CODE_DIR:-$HOME/code}" ]; then
  set -- "${CODE_DIR:-$HOME/code}"
fi
exec "${BASE_DIR}/bin/idea" "$@"
STARTEREOF
chmod 0755 "$STARTER_FILE"

# --- Runtime hook: pre-generate .idea/ via Gradle's own `idea` task if missing ---
STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-idea-open-project--startup.sh"
mkdir -p /usr/share/startup.d
cat > "$STARTUP_FILE" <<'STARTUPEOF'
#!/usr/bin/env bash
# Pre-generate .idea/ (via Gradle's own `idea` task) so opening IntelliJ doesn't hit
# its build-system disambiguation wizard. Best-effort -- never fails the boot.

CB_IDEA_PROJECT_DIR="${CODE_DIR:-$HOME/code}"
CB_IDEA_KIND="__IDEA_KIND__"

if [ -d "$CB_IDEA_PROJECT_DIR" ] && [ ! -d "$CB_IDEA_PROJECT_DIR/.idea" ]; then
  if [ "$CB_IDEA_KIND" = "DEFAULT" ]; then
    if [ -f "$CB_IDEA_PROJECT_DIR/pom.xml" ]; then
      CB_IDEA_KIND=MAVEN
    elif [ -f "$CB_IDEA_PROJECT_DIR/build.gradle" ] || [ -f "$CB_IDEA_PROJECT_DIR/build.gradle.kts" ] || [ -f "$CB_IDEA_PROJECT_DIR/settings.gradle" ] || [ -f "$CB_IDEA_PROJECT_DIR/settings.gradle.kts" ]; then
      CB_IDEA_KIND=GRADLE
    else
      CB_IDEA_KIND=GENERAL
    fi
  fi

  if [ "$CB_IDEA_KIND" = "GRADLE" ] && command -v gradle >/dev/null 2>&1; then
    GRADLE_CMD=gradle
    [ -x "$CB_IDEA_PROJECT_DIR/gradlew" ] && GRADLE_CMD="$CB_IDEA_PROJECT_DIR/gradlew"
    if (cd "$CB_IDEA_PROJECT_DIR" && "$GRADLE_CMD" idea --no-daemon -q) >/tmp/cb-idea-open.log 2>&1; then
      echo "IntelliJ: generated .idea/ for '$(basename "$CB_IDEA_PROJECT_DIR")' via 'gradle idea'"
    else
      echo "IntelliJ: 'gradle idea' failed -- open the project manually the first time (see /tmp/cb-idea-open.log)" >&2
    fi
  fi
  # MAVEN/GENERAL: no headless equivalent -- IntelliJ's own Open wizard handles these
  # fine without the Gradle-vs-Eclipse ambiguity that prompted this in the first place.
fi
STARTUPEOF

sed -i "s/__IDEA_KIND__/${KIND}/" "$STARTUP_FILE"
chmod 0755 "$STARTUP_FILE"

echo "✅ IntelliJ starter patched to open ~/code by default: ${STARTER_FILE}"
echo "✅ .idea/ auto-generation hook installed at ${STARTUP_FILE} (kind=${KIND})"
