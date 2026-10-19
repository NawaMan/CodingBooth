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
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -47)

HERE="$PWD"
VERSION="$(get_booth_version)"
SCRIPT_NAME="$(booth_script_name)"

EXPECT="\
${SCRIPT_NAME} $VERSION — launch a Docker-based development booth.

USAGE:
  ${SCRIPT_NAME} [options]                    Run the current booth.
  ${SCRIPT_NAME} [options] [-- command ...]   Run the command inside the current booth.

OPTIONS
  --build-arg <KEY=VAL>   Add a Docker build-arg which customize the booth image.
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde | lxqt | wayland
  --port <n|RANDOM|NEXT>  Host port → container 10000 (NEXT/RANDOM accept :base)
  --profile <a[,b]>       Overlay .booth/<name>--config.toml and .booth/.<name>--env
                          on the base config (see docs/BOOTH_PROFILES.md)
  --daemon                Run the booth in the background
  --keep-alive            Do not remove the container when stopped
  --no-browser            Do not open the booth UI in a browser when it comes up
  --persist-home          [Experimental] Persist /home/coder across sessions in a named volume
  --writable-booth        Allow writing to .booth/ inside the container (read-only by default)
  --dind                  Enable a Docker-in-Docker sidecar (privileged: asks first)
  --public                Bind to all interfaces with password authentication
  --egress                Enable egress defaults (proxy + enforcement)
  --sudo <true|false>     Enable/disable sudo access (default: true)
  --engine <docker|podman|apple>
                          Container engine to use (default: apple, i.e. Apple
                          container, when installed and running; else docker;
                          else podman. podman and apple are experimental — see
                          docs/PODMAN_SUPPORT.md and docs/CONTAINER_SUPPORT.md)

EXAMPLES:
  ${SCRIPT_NAME} --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  ${SCRIPT_NAME} --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  ${SCRIPT_NAME} -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  BUILD     | Build and publish booth images         | build                                                                   | docs/BOOTH_BUILD.md
  LIFECYCLE | Manage kept-alive booths               | list, start, stop, restart, remove, prune, logs                         | docs/BOOTH_LIFECYCLE.md
  HOME VOL  | Manage persisted home volumes          | home-volume-list, home-volume-export, home-volume-import [Experimental] | docs/BOOTH_HOME.md
  TOOLS     | Copy files and inspect booths          | cp, inspect, stats, top, diff, wait                                     | docs/BOOTH_TOOLS.md
  CONNECT   | Connect to a running booth             | shell, exec                                                             | docs/BOOTH_CONNECT.md
  MESSAGE   | Send messages into a booth             | message                                                                 | docs/BOOTH_MESSAGE.md
  EXPOSE    | Inspect a booth's ports                | expose list                                                             | docs/BOOTH_EXPOSE.md
  CONFIG    | Configure this project's booth         | config                                                                  | docs/BOOTH_CONFIG.md
  EXAMPLE   | Start from an example workspace        | example                                                                 | docs/BOOTH_EXAMPLE.md
  SHOWCASE  | Import a CodingBooths.online showcase  | showcase                                                                | docs/BOOTH_SHOWCASE.md
  PROJECT   | Scaffold project files                 | just-init, template                                                     | docs/BOOTH_EXAMPLE.md
  EXPRESS   | Run from arguments, ignoring .booth/   | express                                                                 | docs/BOOTH_RUN.md

Run '${SCRIPT_NAME} --help <command>'   for command-specific help."

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
