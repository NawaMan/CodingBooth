#!/bin/bash
# bash-language-server reports shellcheck findings here; try removing the quotes below.
set -euo pipefail
name="${1:-World}"
echo "Hello, ${name}!"
