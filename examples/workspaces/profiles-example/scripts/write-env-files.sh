#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Write the sample env files: .booth/.env, .booth/.default--env, .booth/.prod--env.
# They are gitignored (.booth/.gitignore: .env, .*--env), and booth refuses an env
# file that git tracks, so they cannot ship with the example. A file that already
# exists is left alone.

cd "$(dirname "$0")/.."

write() {
    if [[ -e "$1" ]]; then
        echo "kept    $1"
    else
        printf '%s\n' "$2" > "$1"
        echo "wrote   $1"
    fi
}

write .booth/.env          "LEVEL=base"
write .booth/.default--env "LEVEL=default"
write .booth/.prod--env    "LEVEL=prod"
