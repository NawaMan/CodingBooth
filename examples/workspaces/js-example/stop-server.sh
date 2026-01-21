#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Stops the API server and Vite dev server by PID files or port detection.

set -euo pipefail

API_PID_FILE="$HOME/.dev_api_server.pid"
VITE_PID_FILE="$HOME/.dev_vite_server.pid"

stopped=0
failed=0

# Function to kill processes listening on a specific port
kill_by_port() {
    local port="$1"
    # Check if anything is listening on the port and kill it
    if fuser "${port}/tcp" >/dev/null 2>&1; then
        fuser -k "${port}/tcp" >/dev/null 2>&1 || true
        sleep 0.3
        # Force kill if still running
        if fuser "${port}/tcp" >/dev/null 2>&1; then
            fuser -k -9 "${port}/tcp" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    return 1
}

# Function to stop a server by PID file and port
stop_server() {
    local name="$1"
    local pid_file="$2"
    local port="$3"
    
    local stopped_something=false
    
    # Try PID file first
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        
        # Send SIGTERM to the whole process group (negative pid)
        kill -- -"$pid" 2>/dev/null || true
        sleep 0.5
        
        if [[ -d "/proc/$pid" ]]; then
            # Still alive – force kill the entire group
            kill -9 -- -"$pid" 2>/dev/null || true
            echo "⚡️ Force-killed $name (PID: $pid)."
        else
            echo "✅ $name stopped gracefully (PID: $pid)."
        fi
        
        rm -f "$pid_file"
        stopped_something=true
    fi
    
    # Also try to kill by port as fallback (handles orphaned processes)
    if kill_by_port "$port"; then
        if [[ "$stopped_something" == false ]]; then
            echo "✅ $name stopped (found on port $port)."
        fi
        stopped_something=true
    fi
    
    if [[ "$stopped_something" == true ]]; then
        ((stopped++)) || true
    else
        echo "🔴 $name not running."
    fi
}

# Stop both servers
stop_server "API server" "$API_PID_FILE" 3000
stop_server "Vite dev server" "$VITE_PID_FILE" 5173

if [[ $stopped -eq 0 ]]; then
    echo "🔴 No servers were running."
    exit 1
fi
