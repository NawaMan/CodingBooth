#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

export PY_VERSION=${PY_VERSION:-3.12}

if [[ "$CB_VARIANT_TAG" == "ide-notebook" ]]; then
    /opt/workspace/setups/notebook--setup.sh "${PY_VERSION}"
fi
if [[ "$CB_VARIANT_TAG" == "ide-codeserver" ]]; then
    /opt/workspace/setups/codeserver--setup.sh "${PY_VERSION}"
fi