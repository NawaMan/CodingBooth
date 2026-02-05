# Boothfile Example

This example demonstrates using a **Boothfile** instead of a Dockerfile to configure the CodingBooth environment.

## What is a Boothfile?

A Boothfile is a higher-level DSL (Domain-Specific Language) that compiles to a Dockerfile. It provides a simpler, more intuitive syntax for common development environment setup tasks.

## Key Features Demonstrated

### 1. Setup Commands
```
setup python 3.12
setup nodejs 20
```
Automatically calls the appropriate setup scripts (`python--setup.sh`, `nodejs--setup.sh`).

### 2. Install Commands
```
install pip flask requests pytest
install npm typescript prettier
```
Calls package manager install scripts (`pip--install.sh`, `npm--install.sh`).

### 3. Build Arguments
```
arg PY_VERSION=3.12
```
Defines build-time variables that can be used with `${PY_VERSION}` syntax.

### 4. Environment Variables
```
env FLASK_APP=app.py
env FLASK_ENV=development
```
Sets environment variables in the container.

### 5. Heredoc Support
```
run &&<<SETUP
echo "Boothfile example initialized"
date > /tmp/booth-init-time.txt
SETUP
```
Multi-line commands with `&&` joining.

## Usage

```bash
cd examples/workspaces/boothfile-example
booth                    # start the environment
python app.py            # run the Flask app
```

## Generate Dockerfile

To see the generated Dockerfile without running:

```bash
codingbooth --code . --emit-dockerfile
```

## Purpose

This example shows how Boothfile simplifies environment configuration compared to writing raw Dockerfiles. The DSL handles common patterns automatically while still allowing full Docker capabilities when needed.
