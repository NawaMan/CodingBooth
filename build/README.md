# Build Scripts

This directory contains build and setup scripts for the CodingBooth project. All scripts must be run from the **project root directory**.

## Scripts

### cli-build.sh

Builds the CLI binary for multiple platforms.

```bash
./build/cli-build.sh
```

**What it does:**
- Compiles the Go CLI application from `cli/src/cmd/codingbooth/`
- Builds binaries for 6 platform combinations:
  - `linux/amd64`, `linux/arm64`
  - `darwin/amd64`, `darwin/arm64`
  - `windows/amd64`, `windows/arm64`
- Outputs platform-specific binaries to `bin/` directory
- Creates a local `codingbooth` executable in the project root

**Output files:**
- `bin/codingbooth-linux-amd64`
- `bin/codingbooth-linux-arm64`
- `bin/codingbooth-darwin-amd64`
- `bin/codingbooth-darwin-arm64`
- `bin/codingbooth-windows-amd64.exe`
- `bin/codingbooth-windows-arm64.exe`
- `./codingbooth` (current platform)

---

### docker-build.sh

Builds Docker images for all CodingBooth variants.

```bash
# Build all variants locally
./build/docker-build.sh

# Build specific variant(s)
./build/docker-build.sh base
./build/docker-build.sh ide-notebook desktop-xfce

# Build and push to Docker Hub (requires credentials)
./build/docker-build.sh --push base

# Build without cache
./build/docker-build.sh --no-cache base
```

**Options:**
- `--push` - Build multi-arch images and push to Docker Hub with cosign signing
- `--no-cache` - Build without using Docker cache
- `-h, --help` - Show help message

**Variants:**
- `base` - Base image with core tools
- `ide-notebook` - Jupyter notebook variant
- `ide-codeserver` - VS Code in browser variant
- `desktop-xfce` - XFCE desktop environment
- `desktop-kde` - KDE desktop environment

**Environment variables (for --push):**
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token
- `COSIGN_KEY` - Cosign private key content (PEM format)
- `COSIGN_KEY_FILE` - Path to cosign private key file (default: `~/.config/nawaman-codingbooth/cosign.key`)
- `COSIGN_PASSWORD` - Password for encrypted private key

---

### init-go-setup.sh

Installs the Go programming language (v1.24.1).

```bash
./build/init-go-setup.sh
```

**What it does:**
- Detects OS (Linux or macOS) and architecture (amd64 or arm64)
- Downloads the appropriate Go distribution from go.dev
- Installs Go to `/usr/local/go`
- Configures PATH in shell rc file (~/.bashrc or ~/.zshrc)
- Skips installation if correct version is already installed

**Requirements:**
- `curl` for downloading
- `sudo` access for installation to `/usr/local/go`

---

### cosign.pub

Public key for verifying Docker image signatures. This is used to verify that published images were signed by the project maintainer.

```bash
# Verify an image signature
cosign verify --key ./build/cosign.pub nawaman/codingbooth:base-latest
```
