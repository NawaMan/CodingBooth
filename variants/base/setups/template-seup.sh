#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root


command -v envsubst >/dev/null 2>&1 || { echo "❌ 'envsubst' is required but not installed"; exit 1; }

# --- Defaults ---
XXXXXX_VERSION="${1:-0.0.0}"      # Replace this variable with your component version

LEVEL=57                          # See README.md – Profile Ordering (choose an appropriate level)

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-xxxxxx--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-xxxxxx--profile.sh"
STARTER_FILE="/usr/local/bin/xxxxxx"

# Ensure target directories exist
mkdir -p -- "$(dirname -- "$STARTUP_FILE")" \
           "$(dirname -- "$PROFILE_FILE")" \
           "$(dirname -- "$STARTER_FILE")"

# Optional sanity check on LEVEL (non-fatal)
if ! [[ "$LEVEL" =~ ^[0-9]+$ ]]; then
  echo "⚠️  LEVEL is not numeric: $LEVEL"
fi

# ==== Things to do once at call time (as root). ====
# Install packages, create system users/groups, write system configs, etc.



# ---- Create startup file: executed as the normal user at container start ----
# The startup file is invoked by the container entrypoint when the container starts.
#
# ⚠️ WARNING:
#   Scripts here run every time the container starts.
#   Heavy setup or large initialization steps will slow down container startup.
#   Keep this section as light and idempotent as possible.
#
export XXXXXX_VERSION
envsubst '$XXXXXX_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==== Things to do once at container start (as the user). ====
# - You can use $XXXXXX_VERSION in this block.
# - If the user stops/starts or pauses/resumes the container, this runs again.
#   Make it idempotent.

# Example "run once" sentinel:
# SENTINEL="$HOME/.xxxxxx-startup-done"
# [[ -f "$SENTINEL" ]] && exit 0
# touch "$SENTINEL"

EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at the beginning of each user shell session ----
#
# ⚠️ WARNING:
#   Code in this file runs on every shell login or new terminal session.
#   Complex or slow logic will make interactive shells feel sluggish.
#   Keep this section focused on lightweight tasks like environment variables or PATH tweaks.
#
envsubst '$XXXXXX_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: XXXXXX – $XXXXXX_VERSION

# ==== Things to do at shell login (as the user). ====
# - You can use $XXXXXX_VERSION in this block.
# - Keep this lightweight (export vars, tweak PATH, aliases, etc.).

# Example PATH guard:
# case ":$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:$PATH";; esac

EOF
chmod 644 "${PROFILE_FILE}"

# ---- Create starter wrapper: pre/post steps around the real program ----
#
# ⚠️ WARNING:
#   This wrapper runs every time the user starts the associated application.
#   Adding heavy or slow operations here will delay app launch.
#   Keep this minimal unless startup instrumentation or checks are required.
#
envsubst '$XXXXXX_VERSION' > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==== Things to do around the executable (as the user). ====
# - You can use $XXXXXX_VERSION in this block.

# Hand off to the real binary (replace with actual path):
# exec /usr/local/bin/real-xxxxxx "$@"

EOF
chmod 755 "${STARTER_FILE}"

echo "✅ XXXXXX installation scaffolding created."
echo "• Version: ${XXXXXX_VERSION}"
echo "• Startup file (container start): ${STARTUP_FILE}"
echo "• Profile file (each user shell): ${PROFILE_FILE}"
echo "• Starter file (user-facing cmd) : ${STARTER_FILE}"
echo
echo "Tip: You can 'source' the profile file in the current shell if needed."
