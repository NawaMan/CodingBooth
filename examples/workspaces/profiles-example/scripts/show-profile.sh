#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Print, inside the booth, every setting the base and the profiles touch -- one
# KEY=value per line, empty when unset. The test greps these lines.

echo "PORT=${BOOTH_HOST_PORT:-}"              # scalar `port`: the later layer wins
echo "FROM_BASE=${FROM_BASE:-}"               # run-args of config.toml: always there
echo "FROM_DEFAULT=${FROM_DEFAULT:-}"         # run-args of default--config.toml
echo "FROM_PROD=${FROM_PROD:-}"               # run-args of prod--config.toml
echo "LEVEL=${LEVEL:-}"                       # env files: .env, then each profile's
