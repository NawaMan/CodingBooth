#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

sed -i "s|\*\*Current Version:\*\* v[^ ]*|\*\*Current Version:\*\* v${VERSION}|" README.md

if git diff --quiet README.md; then
  echo "README.md already up to date"
else
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git add README.md
  git commit -m "Update README version to v${VERSION}"
  git push
fi
