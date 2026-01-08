#########################################################################################
## Workspace Launcher Configuration (ws--config.sh)                                    ##
##                                                                                     ##
## This file customizes how `workspace` starts the container.                          ##
## It is sourced automatically if present.                                             ##
##                                                                                     ##
## Location / precedence (highest → lowest):                                           ##
##   1) Command-line args                                                              ##
##   2) Values from this config file (ws--config.sh)                                   ##
##   3) Environment variables (exported before launch)                                 ##
##   4) Built-in defaults                                                              ##
##                                                                                     ##
## Tip: You can also set ARGS+=(...) in this file to pre-apply CLI flags.              ##
#########################################################################################

### -------------------------------------------------------------------------------------
### General
### -------------------------------------------------------------------------------------
# DRYRUN=false          # Print docker commands without executing them
# VERBOSE=false         # Extra debug output, banners, and printed commands
# DAEMON=false          # Run container in background (no commands after `--`)

### -------------------------------------------------------------------------------------
### Image selection (precedence: IMAGE_NAME > DOCKER_FILE > prebuilt VARIANT/VERSION)
### -------------------------------------------------------------------------------------
# VARIANT=base          # One of: base | notebook | codeserver | desktop-{xfce,kde}
# VERSION=latest        # Prebuilt version tag (default: latest)

# IMAGE_NAME=           # Full image reference (e.g. repo/name:tag). If set, no build/pull logic runs.
# DOCKER_FILE=          # Path to Dockerfile OR a directory containing ws--Dockerfile for local build
# DO_PULL=false         # When using a prebuilt image, force `docker pull` even if present locally

### -------------------------------------------------------------------------------------
### Identity & paths
### -------------------------------------------------------------------------------------
# WORKSPACE_PATH="$(pwd)"  # Host path mounted to /home/coder/workspace
# CONTAINER_NAME=          # Container name; default derives from WORKSPACE_PATH basename
#                          # (If you want a stable name, prefer setting it via ARGS, e.g.:
#                          #   ARGS+=("--name" "my-workspace"))

### -------------------------------------------------------------------------------------
### UID/GID mapping (controls user inside the container)
### -------------------------------------------------------------------------------------
# HOST_UID=               # Defaults to current host UID (id -u)
# HOST_GID=               # Defaults to current host GID (id -g)

### -------------------------------------------------------------------------------------
### Port selection
### -------------------------------------------------------------------------------------
# WORKSPACE_PORT=10000    # Host port mapped to container 10000.
#                         # Allowed values:
#                         #   - A number between 10000 and 65535
#                         #   - NEXT   (pick the next free port ≥ 10000)
#                         #   - RANDOM (pick a random free port > 10000)

### -------------------------------------------------------------------------------------
### Environment file passed to `docker run` (NOT sourced by this script)
### -------------------------------------------------------------------------------------
# CONTAINER_ENV_FILE=     # If unset, the script auto-uses "${WORKSPACE_PATH}/.env" when it exists.
#                         # Set to "none" to explicitly disable --env-file usage.
#                         # Common keys: PASSWORD, JUPYTER_TOKEN, TZ, HTTP(S)_PROXY, AWS_*, GH_TOKEN

### -------------------------------------------------------------------------------------
### Docker-in-Docker (DinD) sidecar
### -------------------------------------------------------------------------------------
# DIND=false              # If true, starts a docker:dind sidecar and wires DOCKER_HOST to it.
#                         # Note: This provides a dev-only Docker daemon with limitations.

### -------------------------------------------------------------------------------------
### Advanced: extra Docker args
### -------------------------------------------------------------------------------------
# BUILD_ARGS=( )          # Extra args for `docker build` when DOCKER_FILE is used
# RUN_ARGS=( )            # Extra args for `docker run` (e.g., RUN_ARGS=(-e TZ=UTC))
# ARGS+=( )               # Pre-applied CLI flags merged before command-line parameters
#                         # Example: ARGS+=("--name" "my-workspace" "-p" "8080:8080")

### -------------------------------------------------------------------------------------
### Command to run inside the container when using COMMAND mode
### (i.e., after `--` on the CLI). Prefer passing commands via CLI.
### -------------------------------------------------------------------------------------
# CMDS=( )                # Example: CMDS=(bash -lc "make test")

#########################################################################################
## Examples                                                                            ##
#########################################################################################
# # Use a prebuilt image with Codeserver, random open port, and custom name:
# VARIANT=codeserver
# VERSION=latest
# WORKSPACE_PATH="$HOME/projects/my-app"
# ARGS+=("--port" "RANDOM" "--name" "my-app")

# # Force pull the prebuilt image and disable automatic .env usage:
# DO_PULL=true
# CONTAINER_ENV_FILE=none

# # Local build from a workspace Dockerfile directory containing ws--Dockerfile:
# DOCKER_FILE="./"
# BUILD_ARGS+=(--no-cache)

# # Provide additional runtime env and volume:
# RUN_ARGS+=(-e TZ=America/Toronto -v "$HOME/.cache:/home/coder/.cache")
