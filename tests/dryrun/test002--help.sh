#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

HOST_UID="XXXXX"
HOST_GID="XXXXX"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

# Just check the USAGE section (first 17 lines) - the full help is ~98 lines
ACTUAL=$(run_coding_booth help | head -29)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
codingbooth $VERSION — launch a Docker-based development booth.

USAGE:
  codingbooth [options]                    Run the current booth.
  codingbooth [options] [-- command ...]   Run the command inside the current booth.

OPTIONS
  --build-arg <KEY=VAL>   Add a Docker build-arg which customize the booth image.
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde
  --port <n|RANDOM|NEXT>  Host port → container 10000
  --daemon                Run the booth in the background
  --dind                  Enable a Docker-in-Docker sidecar
  --public                Bind to all interfaces with password authentication
  --sandboxed             Enable sandbox defaults (proxy + enforcement)
  --sudo <true|false>     Enable/disable sudo access (default: true)
  --no-sudo               Shorthand for --sudo false

EXAMPLES:
  codingbooth --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  codingbooth --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  codingbooth -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  BUILD     | Build and publish booth images   | build
  LIFECYCLE | Manage kept-alive booths         | list, start, stop, restart, remove, prune
  CONNECT   | Connect to a running booth       | shell, exec
  PROJECT   | Set up and scaffold new projects | example, config, template

Run 'codingbooth --help <command>'   for command-specific help."

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "1" "Help output matches expected"
else
  print_test_result "false" "$0" "1" "Help output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
