#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# This script will always be installed by root.
HOME=/root


PROFILE_FILE="/etc/profile.d/57-cb-jenv--profile.sh"

# ----- idempotent/atomic write of PROFILE_FILE -----
mkdir -p "$(dirname "$PROFILE_FILE")"
cat >"$PROFILE_FILE" <<'EOF'

JENV_ROOT="${HOME}/.jenv"
JENV_BIN="${JENV_ROOT}/bin/jenv"

# install jenv to ~/.jenv (idempotent)
if [ ! -x "${JENV_BIN}" ]; then
  # github.com intermittently answers 429/503 during a full build sweep and git
  # has no --retry of its own. Clear the partial clone before retrying — git
  # refuses to clone into a non-empty directory.
  for attempt in 1 2 3; do
    if git clone --depth=1 https://github.com/jenv/jenv.git "${JENV_ROOT}"; then break; fi
    if [ "$attempt" = 3 ]; then echo "❌ jenv clone failed after 3 attempts"; exit 1; fi
    echo "  ⚠️  clone failed — retrying in $((attempt * 5))s ..."
    rm -rf "${JENV_ROOT}"
    sleep $((attempt * 5))
  done
fi

case ":$PATH:" in
  *":$JENV_ROOT/bin:"*) : ;;  # already in PATH, do nothing
  *) export PATH="$JENV_ROOT/bin:$PATH" ;;
esac

# initialize the shell hooks
eval "$(${JENV_BIN} init -)"

if [ ! -e "${JENV_ROOT}/plugins/export" ]; then
  jenv enable-plugin export
fi

EOF
