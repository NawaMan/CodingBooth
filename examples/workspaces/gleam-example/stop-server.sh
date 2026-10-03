#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stop the Wisp app started by start-server.sh. `gleam run` execs the BEAM, so the
# pid it wrote is the VM itself; the pattern match catches a run started by hand.

if [[ -f /tmp/gleam-example.pid ]]; then
    kill "$(cat /tmp/gleam-example.pid)" 2>/dev/null || true
    rm -f /tmp/gleam-example.pid
fi
pkill -f "gleam_example@@main" 2>/dev/null || true
pkill -f "gleam run" 2>/dev/null || true
exit 0
