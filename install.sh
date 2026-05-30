#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# CodingBooth Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/NawaMan/CodingBooth/main/install.sh | bash

set -euo pipefail

curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
./booth install

echo ""
echo "Use ./booth from this directory, or run it via a full path."
echo ""
