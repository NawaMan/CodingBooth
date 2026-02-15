#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "Setting up CodingBooth development environment..."
echo ""

# Activate git hooks
git config core.hooksPath "$REPO_ROOT/.githooks"
echo "Git hooks activated (.githooks/)"

echo ""
echo "Done! Your development environment is ready."
