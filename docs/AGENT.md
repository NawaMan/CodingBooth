# CodingBooth Agent Instructions

**Purpose:** Operational guidance for AI agents to configure and manage CodingBooth development environments.

---

## Am I in a CodingBooth?

**Check if you're inside a CodingBooth container:**

```bash
# Any of these indicate you're in a booth:
[[ -d /opt/codingbooth ]]               # CodingBooth directory exists
command -v codingbooth-info &>/dev/null # CodingBooth info command available
[[ -f /opt/codingbooth/version.txt ]]   # Version file exists
```

**If YES (inside a booth):** Continue reading this document.

**If NO (not in a booth):** Wrong guide! Read the setup guide instead:
- https://github.com/NawaMan/CodingBooth/blob/main/docs/AGENT_SETUP.md

That guide helps you assist users in setting up CodingBooth from scratch. Once the booth is running, come back here.

---

## First Things First

```bash
codingbooth-info                        # What environment am I in?
ls /opt/codingbooth/setups/             # What tools can I easily add?
cat /home/coder/code/.booth/Dockerfile  # What's already configured?
```

**You are running as the `coder` user** (not root). You have passwordless `sudo` available when needed for system operations. Setup scripts run as root during image build.

---

## Critical Mental Model

**You are INSIDE the container.** This changes everything:

| Location | Persistence | What to do |
|----------|-------------|------------|
| `/home/coder/code/` | Persists (mounted from host) | Project files, `.booth/` config |
| `/home/coder/` (outside `code/`) | Ephemeral | Lost on restart |
| `/opt/`, `/usr/`, `/etc/` | Ephemeral | Lost on restart |

**Key insight:** To make changes permanent, modify files in `/home/coder/code/.booth/` — these are the source of truth that rebuild the container.

---

## Quick Reference: Where Things Are

```
/home/coder/code/              # Project root (PERSISTENT - mounted from host)
├── .booth/
│   ├── config.toml            # Runtime config (variant, ports, run-args, etc.)
│   ├── Dockerfile             # Custom image build
│   ├── setups/                # Custom setup scripts (you create these)
│   ├── home/                  # Files copied to ~ (override mode)
│   ├── home-seed/             # Files copied to ~ (no-clobber mode)
│   └── startup.sh             # Custom startup hook (runs as user)

/opt/codingbooth/              # CodingBooth resources
├── README.md                  # Main documentation
├── version.txt                # Current version
├── AGENT.md                   # This file!
├── variants/                  # Dockerfiles for all variants (for reference)
└── setups/                    # Built-in setup scripts (READ THESE FIRST)
    ├── python--setup.sh
    ├── node--setup.sh
    ├── java--setup.sh
    ├── go--setup.sh
    ├── codingbooth-info       # Quick info about current environment
    └── ...                    # Many more — list with: ls /opt/codingbooth/setups/

/etc/profile.d/                # Shell profile scripts (sourced on login)
/usr/share/startup.d/          # Startup scripts (run once per container boot)
/usr/local/bin/                # Executable wrappers
```

---

## Decision Tree: Adding Dependencies

```
User needs a tool/dependency
           │
           ▼
┌──────────────────────────────────────┐
│ Check /opt/codingbooth/setups/ first │
│ ls /opt/codingbooth/setups/          │
└──────────────────────────────────────┘
           │
           ▼
    Built-in exists?
      /          \
    YES           NO
     │             │
     ▼             ▼
  Add to       Simple install?
  Dockerfile   (apt-get works)
     │            /      \
     │          YES       NO
     │           │         │
     │           ▼         ▼
     │     apt-get in   Create custom
     │     Dockerfile   setup script
     │           │         │
     └─────┬─────┴─────────┘
           ▼
   Rebuild container
   (user runs: ./booth)
```

---

## Action: Add a Built-in Tool

**Example:** User asks for Python environment.

1. **Check if setup exists:**
   ```bash
   ls /opt/codingbooth/setups/ | grep python
   ```

2. **Read the setup script** to understand what it does:
   ```bash
   cat /opt/codingbooth/setups/python--setup.sh
   ```

3. **Create or update `.booth/Dockerfile`:**
   ```dockerfile
   # syntax=docker/dockerfile:1.7
   ARG CB_VARIANT_TAG=codeserver
   ARG CB_VERSION_TAG=latest
   FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

   RUN python--setup.sh
   ```

4. **Tell user to rebuild:**
   > "I've added Python to your Dockerfile. Restart the booth to apply: `./booth`"

---

## Action: Add a Simple apt Package

**Example:** User needs `htop`.

1. **Update `.booth/Dockerfile`:**
   ```dockerfile
   # syntax=docker/dockerfile:1.7
   ARG CB_VARIANT_TAG=base
   ARG CB_VERSION_TAG=latest
   FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

   RUN apt-get update && apt-get install -y htop && rm -rf /var/lib/apt/lists/*
   ```

2. **Tell user to rebuild.**

---

## Action: Create a Custom Setup Script

**When:** Tool requires environment variables, profile scripts, user-specific config, or complex installation.

1. **Create setup script** at `.booth/setups/<tool>--setup.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   # Install the tool (runs as root during build)
   curl -fsSL https://example.com/install.sh | bash

   # Create profile script (for PATH, env vars)
   cat > /etc/profile.d/65-cb-<tool>--profile.sh << 'EOF'
   export TOOL_HOME="/opt/tool"
   export PATH="$TOOL_HOME/bin:$PATH"
   EOF
   chmod 644 /etc/profile.d/65-cb-<tool>--profile.sh

   # Create startup script (one-time init per boot, runs as user)
   cat > /usr/share/startup.d/65-cb-<tool>--startup.sh << 'EOF'
   #!/usr/bin/env bash
   # Create user config if missing
   [[ -f ~/.tool-config ]] || echo "default config" > ~/.tool-config
   EOF
   chmod 755 /usr/share/startup.d/65-cb-<tool>--startup.sh
   ```

2. **Reference in Dockerfile:**
   ```dockerfile
   # syntax=docker/dockerfile:1.7
   ARG CB_VARIANT_TAG=base
   ARG CB_VERSION_TAG=latest
   FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

   COPY .booth/setups/<tool>--setup.sh /tmp/
   RUN chmod +x /tmp/<tool>--setup.sh && /tmp/<tool>--setup.sh
   ```

   > **Why `/tmp/`?** Custom setup scripts only run once during build. Built-in scripts in `/opt/codingbooth/setups/` are in PATH for reuse. Your custom scripts just need to execute during the build step.

3. **Tell user to rebuild.**

**Level ranges for ordering:**
| Level | Purpose                              |
|-------|--------------------------------------|
| 50–54 | Core CodingBooth                     |
| 55–59 | OS/UI (desktop, browsers)            |
| 60–64 | Languages (Python, Java, Node, Go)   |
| 65–69 | Language extensions (venv, linters)  |
| 70–74 | Dev tools (IDEs, editors)            |
| 75–79 | Tool extensions (plugins, kernels)   |

---

## Action: Add User-Level Config/Dotfiles

**Team-shared (override):** `.booth/home/`
- Files copied to `/home/coder/` at startup
- **Overwrites** existing files
- Use for: enforced team configs

**Team-shared (seed):** `.booth/home-seed/`
- Files copied to `/home/coder/` at startup
- **Does NOT overwrite** existing files
- Use for: default templates users can customize

**Example:** Add team `.gitconfig`
```
.booth/home/.gitconfig    # Enforced for everyone
```

---

## Action: Add Custom Startup Logic

**For simple project-specific startup:** Use `.booth/startup.sh`
- Runs once at container start, as the `coder` user
- Good for: project-specific initialization, starting background services
- Simpler than creating a full setup script

```bash
# .booth/startup.sh
#!/usr/bin/env bash
# Start a background service for this project
npm run dev:server &
```

**For tool installation with startup needs:** Create a setup script in `.booth/setups/`
- Setup scripts run as root during image build
- They can create proper startup scripts in `/usr/share/startup.d/`
- Better for: reusable tools, system-level configuration

**When to use which:**
| Need | Use |
|------|-----|
| Project-specific startup commands | `.booth/startup.sh` |
| Tool that needs PATH/env vars | Setup script with profile in `/etc/profile.d/` |
| Tool with user-level init | Setup script with startup in `/usr/share/startup.d/` |

---

## Action: Experiment Before Committing

**Pattern:** Try ephemeral changes first, persist only if they work.

```
Agent: "Let me try installing this package to see if it works..."

# Ephemeral test (will be lost on restart)
pip install some-package --break-system-packages
# or
npm install -g some-tool

Agent: "That worked! Let me add it to your Dockerfile so it persists..."

# Then update .booth/Dockerfile
```

**This is valuable because:**
- Fast feedback loop
- No rebuild needed for testing
- Only commit working solutions to config

---

## Action: Modify Runtime Config

**File:** `.booth/config.toml`

**Common settings:**
```toml
# Select variant
variant = "codeserver"    # base, notebook, codeserver, desktop-xfce, desktop-kde

# Port mapping
port = 10000              # or "NEXT" or "RANDOM"

# Environment variables for container
run-args = ["-e", "TZ=UTC", "-e", "MY_VAR=value"]

# Extra volumes
run-args = ["-v", "/host/path:/container/path"]

# Default command
cmds = ["bash", "-lc", "npm start"]

# Build arguments
build-args = ["--build-arg", "NODE_VERSION=20"]
```

**Changes take effect on next `./booth` run.**

---

## Action: Find Information About the Environment

**Quick overview:** Run `codingbooth-info` to see version, variant, and key paths:
```bash
codingbooth-info
```

**Read setup scripts** to understand paths, env vars, and configuration:
```bash
cat /opt/codingbooth/setups/python--setup.sh
cat /opt/codingbooth/setups/node--setup.sh
```

Setup scripts are the **source of truth** for:
- Where tools are installed
- What environment variables are set
- What profile/startup scripts are created
- What wrapper commands exist

---

## What NOT to Do

| Don't                                                    | Do Instead                                    |
|----------------------------------------------------------|-----------------------------------------------|
| Install tools directly in running container (ephemeral)  | Add to `.booth/Dockerfile`                    |
| Edit files in `/etc/`, `/opt/`, `/usr/` directly         | Create setup scripts in `.booth/setups/`      |
| Tell user to "just run `curl \| bash`"                   | Add proper setup to Dockerfile                |
| Hardcode paths without checking setup scripts            | Read `/opt/codingbooth/setups/*.sh` first     |
| Assume tool locations                                    | Check setup scripts for actual paths/env vars |

**Exception:** Ephemeral installs are OK for **experimentation** before committing to config.

---

## Troubleshooting

**"Tool not found after restart"**
- Was it added to `.booth/Dockerfile`? Ephemeral installs don't persist.

**"Permission denied"**
- Setup scripts run as root during build. User-level changes go in startup scripts or `.booth/home/`.

**"Changes not taking effect"**
- User needs to restart booth: `./booth`

**"Which setup script should I use?"**
- List available: `ls /opt/codingbooth/setups/`
- Read it: `cat /opt/codingbooth/setups/<name>--setup.sh`

---

## Summary Checklist

When user asks to set up a tool/environment:

- [ ] Check `/opt/codingbooth/setups/` for built-in setup
- [ ] Read the setup script to understand what it does
- [ ] If no built-in: decide between apt-get or custom setup script
- [ ] Update `.booth/Dockerfile` with the setup
- [ ] If user config needed: add to `.booth/home/` or `.booth/home-seed/`
- [ ] If runtime config needed: update `.booth/config.toml`
- [ ] Tell user to restart booth to apply changes
- [ ] For quick tests: OK to install ephemerally first, then persist
