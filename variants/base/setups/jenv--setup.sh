#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROFILE_FILE="/etc/profile.d/57-ws-jenv--profile.sh"

# ----- idempotent/atomic write of PROFILE_FILE -----
mkdir -p "$(dirname "$PROFILE_FILE")"
tmp="$(mktemp "${PROFILE_FILE}.XXXX")"
cat >"$tmp" <<'EOF'

JENV_ROOT="${HOME}/.jenv"
JENV_BIN="${JENV_ROOT}/bin/jenv"

# install jenv to ~/.jenv (idempotent)
if [ ! -x "${JENV_BIN}" ]; then
  git clone --depth=1 https://github.com/jenv/jenv.git "${JENV_ROOT}"
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

# Only replace if content changed
if [ -f "$PROFILE_FILE" ] && cmp -s "$tmp" "$PROFILE_FILE"; then
  rm -f "$tmp"
else
  install -m 755 "$tmp" "$PROFILE_FILE"
fi
