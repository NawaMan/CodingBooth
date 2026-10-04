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

# Just check the USAGE section - the full help is ~98 lines
ACTUAL=$(run_coding_booth help)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -42)

HERE="$PWD"
VERSION="$(get_booth_version)"

EXPECT="\
codingbooth $VERSION — launch a Docker-based development booth.

USAGE:
  codingbooth [options]                    Run the current booth.
  codingbooth [options] [-- command ...]   Run the command inside the current booth.

OPTIONS
  --build-arg <KEY=VAL>   Add a Docker build-arg which customize the booth image.
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde | lxqt | wayland
  --port <n|RANDOM|NEXT>  Host port → container 10000 (NEXT/RANDOM accept :base)
  --daemon                Run the booth in the background
  --no-browser            Do not open the booth UI in a browser when it comes up
  --hide-welcome          Do not print the welcome banner in booth shells
  --dind                  Enable a Docker-in-Docker sidecar (privileged: asks first)
  --dind-allowed          Start a --dind booth without asking
  --privileged-allowed    Start a booth with --privileged-like run-args without asking
  --public                Bind to all interfaces with password authentication
  --ok-public             Required with --public if another port is already published
  --egress                Enable egress defaults (proxy + enforcement)
  --sudo <true|false>     Enable/disable sudo access (default: true)
  --no-sudo               Shorthand for --sudo false
  --rootless              Skip the Linux rootless/userns-remap refusal (unsupported)
  --engine <docker|podman|apple>
                          Container engine to use (default: docker; podman and
                          apple, i.e. Apple container, are experimental — see
                          docs/PODMAN_SUPPORT.md and docs/CONTAINER_SUPPORT.md)

EXAMPLES:
  codingbooth --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  codingbooth --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  codingbooth -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  BUILD     | Build and publish booth images   | build                                                                   | docs/BOOTH_BUILD.md
  LIFECYCLE | Manage kept-alive booths         | list, start, stop, restart, remove, prune                               | docs/BOOTH_LIFECYCLE.md
  HOME VOL  | Manage persisted home volumes    | home-volume-list, home-volume-export, home-volume-import [Experimental] | docs/BOOTH_HOME.md
  CONNECT   | Connect to a running booth       | shell, exec                                                             | docs/BOOTH_CONNECT.md
  MESSAGE   | Send messages into a booth       | message                                                                 | docs/BOOTH_MESSAGE.md
  EXPOSE    | Inspect a booth's ports          | expose list                                                             | docs/BOOTH_EXPOSE.md
  PROJECT   | Set up and scaffold new projects | example, config, template, showcase                                     | docs/BOOTH_EXAMPLE.md

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
