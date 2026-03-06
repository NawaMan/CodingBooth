#!/usr/bin/env bash
# Make it so that we use git if GH_TOKEN is set (also GIT_USER and GIT_EMAIL)
# even if the .git is set to be from SSH.

set -euo pipefail

echo "[git-on-token] Starting Git setup..."

# ---- Ensure required variables exist ----

require_var () {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "[git-on-token] ERROR: $name is not set"
        exit 1
    fi
}

require_var GH_TOKEN
require_var GIT_USER
require_var GIT_EMAIL

# ---- Export token for gh ----

export GH_TOKEN="$GH_TOKEN"

# ---- Ensure required tools exist ----

command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }
command -v gh  >/dev/null 2>&1 || { echo "gh not found"; exit 1; }

# ---- Configure git identity ----

echo "[git-on-token] Configuring git identity"

git config --global user.name  "$GIT_USER"
git config --global user.email "$GIT_EMAIL"

# ---- Prevent interactive credential prompts ----

git config --global credential.interactive never

# ---- Setup gh as git credential helper ----

echo "[git-on-token] Configuring gh credential helper"

gh auth setup-git >/dev/null

# ---- Rewrite SSH GitHub URLs to HTTPS (without modifying repo) ----

echo "[git-on-token] Enabling GitHub SSH → HTTPS rewrite"

git config --global --unset-all url."https://github.com/".insteadOf 2>/dev/null || true

git config --global --add url."https://github.com/".insteadOf git@github.com:
git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/

# ---- Validate token works ----

echo "[git-on-token] Validating GitHub authentication"

if ! gh api user >/dev/null 2>&1; then
    echo "[git-on-token] ERROR: GitHub token invalid"
    exit 1
fi

echo "[git-on-token] Git setup complete"
