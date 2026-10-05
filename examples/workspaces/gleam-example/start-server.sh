#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Start the Wisp app on port 8000 in the background and wait until it answers.
# The first run downloads the Hex packages and compiles them, so allow a while.

cd "$(dirname "$0")"

if curl -fs --max-time 2 http://localhost:8000/ >/dev/null 2>&1; then
    echo "Already running on http://localhost:8000"
    exit 0
fi

# Compile first, in the foreground, so a build error is shown here and not lost in the log.
gleam build || exit 1

nohup gleam run > /tmp/gleam-example.log 2>&1 &
echo $! > /tmp/gleam-example.pid

for _ in $(seq 1 60); do
    if curl -fs --max-time 2 http://localhost:8000/ >/dev/null 2>&1; then
        echo "Serving on http://localhost:8000  (log: /tmp/gleam-example.log)"
        echo "From the host: booth port + 8000 — run 'booth--expose list' to see it"
        exit 0
    fi
    sleep 1
done

echo "Server did not answer within 60s; log follows:" >&2
cat /tmp/gleam-example.log >&2
exit 1
