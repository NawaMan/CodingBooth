#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select nodejs+npm-install

# Restore pre-installed node_modules from image cache if missing
if [ -d /opt/npm-cache/node_modules ] && [ ! -d node_modules ]; then
  echo "📦 Restoring cached node_modules ..."
  cp -a /opt/npm-cache/node_modules .
fi
