#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--no-kubens]

Examples:
  $0                # install kubectx + kubens (recommended)
  $0 --no-kubens    # install only kubectx

Notes:
- Both tools come from the same upstream repo (ahmetb/kubectx),
  so this single setup ships them as a pair.
- Installs to /usr/local/bin/{kubectx,kubens}
- Bash completions placed in /etc/bash_completion.d/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

WITH_KUBENS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-kubens) WITH_KUBENS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ca-certificates
rm -rf /var/lib/apt/lists/*

REPO_DIR=/opt/kubectx
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "⬇️  Cloning ahmetb/kubectx ..."
  # github.com intermittently answers 429/503 during a full build sweep and git
  # has no --retry of its own. Clear the partial clone before retrying — git
  # refuses to clone into a non-empty directory.
  for attempt in 1 2 3; do
    if git clone --depth 1 https://github.com/ahmetb/kubectx "$REPO_DIR"; then break; fi
    if [ "$attempt" = 3 ]; then echo "❌ kubectx clone failed after 3 attempts"; exit 1; fi
    echo "  ⚠️  clone failed — retrying in $((attempt * 5))s ..."
    rm -rf "$REPO_DIR"
    sleep $((attempt * 5))
  done
else
  echo "ℹ️ Reusing existing $REPO_DIR"
fi

ln -sfn "$REPO_DIR/kubectx" /usr/local/bin/kubectx
install -d /etc/bash_completion.d
ln -sfn "$REPO_DIR/completion/kubectx.bash" /etc/bash_completion.d/kubectx

if [[ $WITH_KUBENS -eq 1 ]]; then
  ln -sfn "$REPO_DIR/kubens" /usr/local/bin/kubens
  ln -sfn "$REPO_DIR/completion/kubens.bash" /etc/bash_completion.d/kubens
fi

echo "✅ kubectx installed."
echo -n "   kubectx → "; command -v kubectx >/dev/null && echo ok || echo missing
if [[ $WITH_KUBENS -eq 1 ]]; then
  echo -n "   kubens  → "; command -v kubens >/dev/null && echo ok || echo missing
fi

cat <<'EON'
ℹ️ Ready to use:
- kubectx <ctx>   switch kubectl context
- kubens  <ns>    switch kubectl namespace
- Both honor KUBECONFIG / ~/.kube/config from your existing kubectl install.
- See: https://github.com/ahmetb/kubectx
EON
