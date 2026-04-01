#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stop the Python HTTP server running on port 8080

pkill -f "python -m http.server 8080" 2>/dev/null || true
