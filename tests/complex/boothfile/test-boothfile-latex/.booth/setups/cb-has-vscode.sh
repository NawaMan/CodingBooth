#!/bin/bash
# Returns 0 if VS Code / code-server is available, 1 otherwise.

command -v code-server &>/dev/null && exit 0
command -v code &>/dev/null && exit 0
exit 1
