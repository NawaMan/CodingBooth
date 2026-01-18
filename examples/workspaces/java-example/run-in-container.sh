#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Run command from outside

SILENCE=false
for arg in "$@"; do
    if [[ "$arg" == "--silence-build" ]]; then
        SILENCE=true
        break
    fi
done
if [[ "$SILENCE" == "false" ]]; then
    echo -e "\033[1mTip: Use \033[34m--silence-build\033[0;1m to silence the build output.\033[0m" >&2
    echo "" >&2

    # Give user time to read the tip.
    sleep 1
fi

../../coding-booth --variant base "$@"
