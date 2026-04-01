#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                     # install latest AWS CDK
  $0 --version 2.150.0   # pin specific version

Notes:
- Installs AWS CDK CLI globally via npm
- Requires Node.js and npm to be installed first (run nodejs--setup.sh)
- Supports bash completion if available
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- check npm/node availability ----
if ! command -v npm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  echo "❌ npm and node are required but not found."
  echo "   Please run nodejs--setup.sh first to install Node.js and npm."
  exit 1
fi

echo "• Node.js: $(node --version)"
echo "• npm:     $(npm --version)"

# ---- install aws-cdk ----
if [[ "$REQ_VER" == "latest" ]]; then
  echo "• Installing AWS CDK (latest) ..."
  npm install -g aws-cdk
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 2.150.0)"; exit 2
  fi
  echo "• Installing AWS CDK v${REQ_VER} ..."
  npm install -g "aws-cdk@${REQ_VER}"
fi

# ---- bash completion ----
if command -v cdk >/dev/null 2>&1; then
  install -d /etc/bash_completion.d
  cat > /etc/bash_completion.d/cdk <<'COMP'
# AWS CDK bash completion
_cdk_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local commands="init synth deploy destroy diff list bootstrap doctor"
  COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}
complete -F _cdk_completions cdk
COMP
fi

# ---- summary ----
INSTALLED_VER="$(cdk --version 2>/dev/null || echo "unknown")"
echo "✅ AWS CDK installed."
echo "   cdk --version → ${INSTALLED_VER}"

cat <<'EON'
ℹ️ Ready to use:
- Try: cdk --version
- Initialize a new CDK app: cdk init app --language typescript
- Synthesize CloudFormation: cdk synth
- Deploy stack: cdk deploy
- Diff changes: cdk diff

Notes:
- AWS CDK requires AWS CLI credentials for deployment operations.
- Use 'aws configure' or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars.
- Supported languages: TypeScript, Python, Java, C#, Go.
EON
