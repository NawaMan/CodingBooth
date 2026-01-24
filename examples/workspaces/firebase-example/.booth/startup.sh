#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ============================================================================
# Demo Startup Script
#
# This script runs at container startup, after all system hooks.
# The aims is to show what sort of thing you can do at the startup of a booth.
# ============================================================================

set -euo pipefail

# Work around for Firebase authentication.
# Home-seeding works by copy files from /etc/cb-home-seed to $HOME.
# However, it only does so if the files do not already exist in $HOME.
# But Firebase installation creates an JSON-empty files there ("{}").

rm -rf ~/.config/configstore/firebase-tools.json
cp /etc/cb-home-seed/.config/configstore/firebase-tools.json ~/.config/configstore/firebase-tools.json
