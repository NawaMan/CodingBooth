#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# CodingBooth Installer
# Usage: curl -fsSL https://codingbooth.io/install.sh | bash

set -euo pipefail

# Download (don't pipe-bash) the wrapper. Piping would trigger the wrapper's
# own pipe-install branch, which delegates back to this script — infinite loop.
curl -fsSL -o booth https://github.com/NawaMan/CodingBooth/releases/download/latest/booth
chmod +x booth
./booth install

echo ""
echo "Use ./booth from this directory, or run it via a full path."
echo ""
