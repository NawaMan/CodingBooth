#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# This script will always be installed by root.
HOME=/root


# 65: after the JDK's 60-cb-jdk--profile.sh. That profile exports JAVA_HOME, so
# sorting before it (this used to be 57) let it overwrite whatever jenv chose, in
# every non-interactive shell (`booth -- mvn ...`) where no prompt hook runs.
PROFILE_FILE="/etc/profile.d/65-cb-jenv--profile.sh"

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

# Enabled before `jenv init`, which is what loads the enabled plugins.
if [ ! -e "${JENV_ROOT}/plugins/export" ]; then
  jenv enable-plugin export
fi

# The JDK profile has already run, so this is the booth's JDK. Captured once:
# ~/.bashrc re-sources this file, by which point JAVA_HOME may be jenv's.
if [ -z "${CB_JENV_SYSTEM_JAVA_HOME+x}" ]; then
  export CB_JENV_SYSTEM_JAVA_HOME="${JAVA_HOME:-}"
fi

# initialize the shell hooks
eval "$(${JENV_BIN} init -)"

# With no version chosen ("system"), `jenv javahome` fails and jenv's export hook
# exports JAVA_HOME="". Put the booth's JDK back, after that hook, every time it runs.
_cb_jenv_java_home_fallback() {
  if [ -z "${JAVA_HOME:-}" ] && [ -n "${CB_JENV_SYSTEM_JAVA_HOME:-}" ]; then
    export JAVA_HOME="$CB_JENV_SYSTEM_JAVA_HOME"
  fi
}
if [ -n "${ZSH_VERSION:-}" ]; then
  case " ${precmd_functions[*]} " in
    *" _cb_jenv_java_home_fallback "*) : ;;
    *) precmd_functions+=(_cb_jenv_java_home_fallback) ;;
  esac
else
  case ";${PROMPT_COMMAND:-};" in
    *";_cb_jenv_java_home_fallback;"*) : ;;
    *) PROMPT_COMMAND="${PROMPT_COMMAND%;}"
       PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_cb_jenv_java_home_fallback" ;;
  esac
fi
_cb_jenv_java_home_fallback

EOF
