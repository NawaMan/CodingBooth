#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select anythingllm+autostart+expose+project-fs+passwordless

# AnythingLLM realpath()s and rejects a symlink out of the jail.
# Docker bind-mounts the project at $JAIL/code via run-args -v @code:...
# Drop a leftover symlink from the old +project-fs so the bind can attach.
JAIL="${STORAGE_DIR:-$HOME/.anythingllm}/anythingllm-fs"
mkdir -p "$JAIL"
if [ -L "$JAIL/code" ]; then
  rm -f "$JAIL/code"
  echo "AnythingLLM project-fs: removed leftover symlink $JAIL/code"
fi
mkdir -p "$JAIL/code"
