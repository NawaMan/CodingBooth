# CodingBooth Setup Guide for AI Agents

**Purpose:** Help AI agents assist users in setting up CodingBooth from scratch (outside the container).

---

## Am I in the Right Place?

**Check if you're OUTSIDE a CodingBooth container:**

```bash
# If this returns false/error, you're OUTSIDE (correct for this guide)
[[ -f /opt/codingbooth/version.txt ]] && echo "INSIDE" || echo "OUTSIDE"
```

**If OUTSIDE:** Continue reading this document.

**If INSIDE a booth:** Stop. Read `/opt/codingbooth/AGENT.md` instead — it has instructions for working inside the booth.

---

## Quick Setup (30 seconds)

For users who want to get started immediately:

```bash
# 1. Install the booth wrapper (run in project root)
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash

# 2. Run the wrapper to set up booth
./ws

# 3. Start the booth
./booth
```

That's it. The booth will build and start with sensible defaults.

---

## Guided Setup

### Step 1: Check Prerequisites

```bash
# Docker must be installed and running
docker version
```

If Docker isn't available, help the user install it first.

### Step 2: Install CodingBooth Wrapper

Run in the project root directory:

```bash
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
```

This creates:
- `./booth` — the launcher script
- `.booth/` — configuration directory

### Step 3: Choose a Variant

| Variant | Best For |
|---------|----------|
| `base` | CLI tools, scripts, automation |
| `notebook` | Data science, Jupyter notebooks |
| `codeserver` | Web-based VS Code IDE |
| `desktop-xfce` | Full Linux desktop (lightweight) |
| `desktop-kde` | Full Linux desktop (feature-rich) |

Create or update `.booth/config.toml`:

```toml
variant = "codeserver"  # or base, notebook, desktop-xfce, desktop-kde
```

### Step 4: Add Development Tools

Create `.booth/Dockerfile` based on project needs:

**Python project:**
```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

RUN python--setup.sh
```

**Node.js project:**
```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

RUN nodejs--setup.sh
```

**Java project:**
```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

RUN jdk--setup.sh
RUN mvn--setup.sh
```

**Go project:**
```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

RUN go--setup.sh
```

**Multiple languages:**
```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

RUN python--setup.sh
RUN nodejs--setup.sh
RUN go--setup.sh
```

### Step 5: Start the Booth

```bash
./booth
```

First run will build the image (may take a few minutes). Subsequent runs are fast.

Access the UI at `http://localhost:10000` (or the port shown in output).

---

## Common Configurations

### Add Credentials from Host

Edit `.booth/config.toml` to mount credentials:

```toml
variant = "codeserver"

run-args = [
    # Git credentials
    "-v", "~/.gitconfig:/etc/cb-home-seed/.gitconfig:ro",
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro",

    # Cloud CLI (pick what you need)
    "-v", "~/.aws:/etc/cb-home-seed/.aws:ro",
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro"
]
```

### Custom Port

```toml
port = 8080        # Fixed port
# or
port = "NEXT"      # Find next available starting from 10000
# or
port = "RANDOM"    # Random available port
```

### Run in Background

```bash
./booth --daemon
```

Access UI at shown URL. Stop with `docker stop <container-name>`.

### Run a Command and Exit

```bash
./booth -- make test
./booth -- npm install
./booth -- python script.py
```

---

## Available Setup Scripts

List all available setup scripts:

```bash
# After booth is running, inside the container:
ls /opt/codingbooth/setups/
```

Or check the repository: https://github.com/NawaMan/CodingBooth/tree/main/variants/base/setups

Common ones:
- `python--setup.sh` — Python with pip, venv
- `nodejs--setup.sh` — Node.js with npm
- `jdk--setup.sh` — Java JDK
- `go--setup.sh` — Go language
- `mvn--setup.sh` — Apache Maven
- `gradle--setup.sh` — Gradle build tool
- `docker-compose--setup.sh` — Docker Compose

---

## Handoff: You're Now Inside

Once the booth is running and the user is inside:

1. The environment switches from "host" to "container"
2. This guide no longer applies
3. Read `/opt/codingbooth/AGENT.md` for inside-the-booth instructions

Tell the user:
> "The booth is running. I'll now follow the in-container guide at `/opt/codingbooth/AGENT.md` for any environment configuration."

---

## Troubleshooting

**"Docker not found"**
→ User needs to install Docker first.

**"Permission denied"**
→ User may need to add themselves to the docker group: `sudo usermod -aG docker $USER` (then logout/login).

**"Port already in use"**
→ Use `port = "NEXT"` in config.toml, or stop the conflicting service.

**"Build takes too long"**
→ First build downloads base image. Subsequent builds use cache. Consider using `--pull` only when updates are needed.

---

## References

- **Full documentation:** https://github.com/NawaMan/CodingBooth/blob/main/README.md
- **Examples:** https://github.com/NawaMan/CodingBooth/tree/main/examples
- **Inside-booth guide:** `/opt/codingbooth/AGENT.md` (available after booth starts)
