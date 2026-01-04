package main

import (
	"fmt"
	"os"
)

func showHelp() {
	scriptName := "workspace"
	if len(os.Args) > 0 {
		scriptName = os.Args[0]
	}

	fmt.Printf(`%s — launch a Docker-based development workspace

USAGE:
  %s <action> [options]
  %s [run options] [--] [command ...]

ACTIONS:
  version                Print the workspace version
  help                   Show this help and exit
  run                    Run the workspace (default if no action given)

GENERAL:
  --verbose              Print extra debugging information
  --dryrun               Print docker commands without executing them
  --pull                 Always pull the image, even if it exists locally
                         (default behavior is to check if the image exists
                          locally and pull it only if it is missing)
  --daemon               Run the workspace container in the background
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST
  --keep-alive           Do not remove the container when stopped
  --skip-main            Do not run Main; load functions only (for testing)
  --config <file>        Load defaults from a config shell file (default: ./ws--config.sh)
  --workspace <path>     Host workspace path to mount at /home/coder/workspace

IMAGE SELECTION (precedence: --image > --dockerfile > prebuilt):
  --image <name>         Use an existing local or remote image (e.g. repo/name:tag)
                         The script will check if the image exists locally and
                         pull it only if it is missing (unless --pull is used).
  --dockerfile <path>    Build locally from Dockerfile (file or directory)
                         If a directory is provided, it must contain ws--Dockerfile.
  --variant <name>       Prebuilt variant:
                           container | ide-notebook | ide-codeserver
                           desktop-xfce | desktop-kde
                         Aliases:
                           notebook | codeserver | xfce | kde
  --version <tag>        Prebuilt version tag (default: latest)

BUILD OPTIONS (only when using --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure
  NOTE: Build args are ignored when using prebuilt images or --image.

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from workspace directory)
  --port <n|RANDOM|NEXT> Host port → container 10000
                         n      : any valid TCP port (1–65535)
                         RANDOM : pick a random free port ≥ 10000
                         NEXT   : pick the next available free port ≥ 10000
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable auto-detection of <workspace>/.env

COMMANDS:
  All arguments after '--' are executed *inside* the container instead of
  starting the default workspace service. Example:
    %s -- -- bash -lc "echo hi"

NOTES:
  - Default image behavior:
        The script checks whether the image exists locally.
        If it is missing, it will be pulled automatically.
        Use --pull to always pull, even if the image already exists.

  - If --env-file is not provided, a <workspace>/.env file will be used when present.
    Specify '--env-file none' to disable this behavior.

  - In daemon mode, do not pass commands after '--'. Stop the container with:
        docker stop <container-name>

  - With --dind, a docker:dind sidecar runs on a private network and the main
    container uses DOCKER_HOST=tcp://<sidecar>:2375.

EXAMPLES:
  # Prebuilt, foreground
  %s --variant container --version latest --workspace /path/to/ws

  # Local build from Dockerfile
  %s --dockerfile ./Dockerfile --workspace . --build-arg FOO=bar

  # Daemon mode with random port
  %s --daemon --variant codeserver --port RANDOM

  # Run a one-off command inside the image
  %s --image my/image:tag -- env | sort

  # Disable automatic .env usage
  %s --env-file none --variant notebook
`, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName)
}
