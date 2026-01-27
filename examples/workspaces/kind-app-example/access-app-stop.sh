#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stops port-forward processes for the TODO app.

echo "Stopping port-forwards..."

pkill -f "port-forward.*svc/web.*3000" 2>/dev/null || true
pkill -f "port-forward.*svc/api.*8080" 2>/dev/null || true
pkill -f "port-forward.*svc/export.*8081" 2>/dev/null || true

echo "Port-forwards stopped."
