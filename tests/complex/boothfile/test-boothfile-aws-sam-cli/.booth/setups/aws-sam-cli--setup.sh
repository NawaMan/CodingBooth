#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--no-completion]

Examples:
  $0                         # install latest AWS SAM CLI
  $0 --version 1.135.0       # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs AWS SAM CLI via pip into /opt/aws-sam-cli venv
- Exposes 'sam' via /usr/local/bin
- Supports amd64 and arm64
- Requires Python 3.8+ (uses system Python or pyenv if available)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates python3 python3-pip python3-venv
rm -rf /var/lib/apt/lists/*

# ---- find usable python ----
PYTHON_BIN=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
    break
  fi
done
[[ -n "$PYTHON_BIN" ]] || { echo "❌ No Python 3 found"; exit 1; }

PY_VER="$("$PYTHON_BIN" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+')"
echo "🐍 Using $PYTHON_BIN ($PY_VER)"

# ---- install into isolated venv ----
VENV_DIR="/opt/aws-sam-cli"
BIN_DIR="/usr/local/bin"

echo "📦 Creating venv at ${VENV_DIR} ..."
"$PYTHON_BIN" -m venv "$VENV_DIR"

if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest aws-sam-cli ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir --upgrade aws-sam-cli
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 1.135.0)"; exit 2
  fi
  echo "⬇️  Installing aws-sam-cli==${REQ_VER} ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir "aws-sam-cli==${REQ_VER}"
fi

# ---- symlink sam to /usr/local/bin ----
ln -sf "$VENV_DIR/bin/sam" "$BIN_DIR/sam"

INSTALLED_VER="$("$BIN_DIR/sam" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")"

# ---- bash completion ----
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  cat > /etc/bash_completion.d/sam <<'COMP'
# AWS SAM CLI bash completion
_sam_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local commands="init validate build deploy package delete local logs traces publish pipeline sync"
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
  fi
}
complete -F _sam_completion sam
COMP
fi

# ---- startup script ----
STARTUP_FILE="/usr/share/startup.d/61-cb-aws-sam-cli--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# AWS SAM CLI startup script
# Copies SAM configuration from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.aws"
AWS_CONFIG_DIR="$HOME/.aws"

# SAM CLI uses the same ~/.aws credentials as AWS CLI
if [[ -d "$CB_SEED_DIR" && ! -d "$AWS_CONFIG_DIR" ]]; then
    mkdir -p "$AWS_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$AWS_CONFIG_DIR/"
    chmod 600 "$AWS_CONFIG_DIR/credentials" 2>/dev/null || true
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ AWS SAM CLI ${INSTALLED_VER} installed at ${VENV_DIR}."
echo "   sam → ${BIN_DIR}/sam"
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: sam --version
- Quick start: sam init

Notes:
- AWS SAM CLI requires AWS CLI credentials to deploy.
  Run 'aws configure' or set env vars (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION).
- SAM CLI uses Docker for local testing (sam local invoke, sam local start-api).
  Enable DinD (--dind) if you want to use 'sam local' features inside the booth.
- To update: re-run with --version <new> or without --version for latest.

Common commands:
  sam init                    # Create a new SAM project
  sam build                   # Build your application
  sam deploy --guided         # Deploy with interactive prompts
  sam local invoke            # Test Lambda functions locally (requires DinD)
  sam local start-api         # Start local API Gateway (requires DinD)
  sam validate                # Validate SAM template
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse AWS credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # AWS credentials (home-seeding: credentials and config)'
echo '      "-v", "~/.aws:/etc/cb-home-seed/.aws:ro"'
echo '  ]'
echo ""
echo "=== Local Testing with Docker ==="
echo "SAM local commands require Docker. Use --dind flag when starting the booth:"
echo ""
echo "  booth --dind"
echo ""
