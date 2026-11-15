#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# missing_required_env <file> — print the entries of an example's
# .cb-tests/requires-env.txt that the current environment does not satisfy,
# space-separated, or nothing when all are. A missing file means nothing is
# required.
#
# The file holds one host environment variable per line; `A|B` means either
# will do. `#` starts a comment, and blank lines and spaces are ignored. A
# variable counts only when it is set and non-empty: an empty AWS key is as
# useless as a missing one.
#
# run-example-tests.sh calls it to report an example SKIPPED, rather than
# FAILED, on a host that has not set what the example needs (aws-env-example,
# which takes AWS credentials from the environment only). Tested by
# tests/setups/test--harness-requires-env.sh. Bash 3.2-safe.
missing_required_env() {
    local file="$1" line name found missing=""
    local -a alts
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [ -n "$line" ] || continue
        found=false
        IFS='|' read -ra alts <<< "$line"
        for name in "${alts[@]}"; do
            [ -n "$name" ] || continue
            if [ -n "${!name:-}" ]; then found=true; fi
        done
        [ "$found" = true ] || missing="${missing:+$missing }$line"
    done < "$file"
    [ -z "$missing" ] || printf '%s\n' "$missing"
}
