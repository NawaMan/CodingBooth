// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func showHelp(version string) {
	scriptName := "coding-booth"
	if len(os.Args) > 0 && os.Args[0] != "" {
		scriptName = filepath.Base(os.Args[0])
	}

	fmt.Printf(`%s — launch a Docker-based development booth (version %s)

USAGE:
  %s version                              (print the CodingBooth version)
  %s help                                 (show this help and exit)
  %s run [options] [--] [command ...]     (run the booth)
  %s [options] [--] [command ...]         (default action: run)

BOOTSTRAP OPTIONS (CLI or defaults; evaluated before environmental variable and config file):
  --code <path>          Host code path to mount at /home/coder/code
                         (default: current directory)
  --config <file>        Path to the config file to load
                         (default: <code>/.booth/config.toml)

CONFIG PRECEDENCE:
  options (CLI) > config file (TOML) > environment (ENV) > defaults
  NOTE: --code and --config are bootstrap options and are taken only from
        CLI (first pass) or defaults.

GENERAL RUN OPTIONS:
  --dryrun               Print docker commands without executing them
  --verbose              Print extra debugging information

IMAGE SELECTION (precedence: --image > --dockerfile > prebuilt):
  --dockerfile <path>    Build locally from a Dockerfile (file or directory)
                         If a directory is provided, it looks for .booth/Dockerfile.
  --image <name>         Use an existing local or remote image (e.g. repo/name:tag)
                         The script checks if the image exists locally and pulls it
                         only if it is missing (unless --pull is used).
  --pull                 Always pull the image, even if it exists locally
                         (default: pull only if the image is missing)
  --variant <name>       Prebuilt variant (examples):
                           base | notebook | codeserver | xfce | kde
                         Aliases:
                           default | ide | desktop | desktop-xfce | desktop-kde
  --version <tag>        Prebuilt version tag (default: latest)

BUILD OPTIONS (only when using --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure
  NOTE: Build args are ignored when using prebuilt images or --image.

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
  --port <n|RANDOM|NEXT> Host port → container 10000
                         n      : any valid TCP port (1–65535)
                         RANDOM : pick a random free port ≥ 10000
                         NEXT   : pick the next available free port ≥ 10000
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable auto-detection of <code>/.env

CONTAINER MODE:
  --daemon               Run the booth container in the background
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST
  --keep-alive           Do not remove the container when stopped

COMMANDS:
  All arguments after '--' are executed *inside* the container instead of starting
  the default booth service. Example:
    %s -- bash -lc "echo hi"

NOTES:
  - Default image behavior:
        The script checks whether the image exists locally.
        If it is missing, it will be pulled automatically.
        Use --pull to always pull, even if the image already exists.

  - If --env-file is not provided, a <code>/.env file will be used when present.
    Specify '--env-file none' to disable this behavior.

  - In daemon mode, do not pass commands after '--'. Stop the container with:
        docker stop <container-name>

  - With --dind, a docker:dind sidecar runs on a private network and the main
    container uses DOCKER_HOST=tcp://<sidecar>:2375.

EXAMPLES:
  # Prebuilt, foreground
  %s --variant base --version latest --code /path/to/code

  # Local build from Dockerfile
  %s --dockerfile ./Dockerfile --code . --build-arg FOO=bar

  # Daemon mode with random port
  %s --daemon --variant codeserver --port RANDOM

  # Run a one-off command inside the image
  %s --image my/image:tag -- env | sort

  # Disable automatic .env usage
  %s --env-file none --variant notebook
`,
		scriptName,
		version,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
	)
}
