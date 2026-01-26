# CodingBooth

**Current Version:** v0.11.0 — [View Changelog](CHANGELOG.md)

CodingBooth delivers fully reproducible, Docker-powered development environments — anywhere, on any machine.
You’ve containerized your app. You’ve containerized your build.
But your development environment? Still a mess of system-wide installs, mismatched versions, and onboarding docs no one reads.

**CodingBooth** fixes that.

With CodingBooth, you can run your IDE, shell, or even an entire Linux desktop inside a container — perfectly mapped to your host user (no root-owned files, no permission headaches). Every developer on your team gets the same consistent environment with zero setup friction.

Whether you want a browser-based VS Code session, a Jupyter notebook environment, or a complete XFCE/KDE desktop accessible through your browser — the CodingBooth images and launcher script make it effortless.

**Result:** a clean, consistent, portable development experience that just works.

# Table of Contents
- [Quick Try](#quick-try)
- [For AI Agents](#for-ai-agents)
- [Installation](#installation)
- [CLI Usage](#cli-usage)
- [Why CodingBooth?](#why-codingbooth)
- [Variants](#variants)
- [Built-in Tools](#built-in-tools)
- [Quick Examples](#quick-examples)
- [Customization](#customization)
- [Guarantees & Limits](#guarantees--limits)
- [How It Works](#how-it-works)
- [`booth` Manual](#booth-manual)
- [Setup Implementation Notes](#setup-implementation-notes)
- [Troubleshooting](#troubleshooting)
- [Implementation Documentation](#implementation-documentation)
- [Community & Feedback](#community--feedback)

## Quick Try

1. Ensure you have Docker installed and running.
2. Clone this repo.
3. cd into it and cd further into `examples/go-example` or any other example in that folder.
4. Run : `../../booth`
5. Wait for a few minutes (may be more for the first run) and visit `http://localhost:10000`
6. Select your IDE and start coding! (note: your code will be in `/home/coder/code` folder).

![Select IDE](DesktopRun.png)

### Optional
7. Inspect `.booth/Dockerfile` and `.booth/config.toml` inside `examples/go-example` and
    see if you can figure out what they are.
8. Try other [examples](https://github.com/NawaMan/CodingBooth/tree/latest/examples) or different [variants](https://github.com/NawaMan/CodingBooth/tree/latest?tab=readme-ov-file#available-variants).
9. Try on your own project,
  1. Run: `curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash`
  2. Create `.booth/Dockerfile` and `.booth/config.toml` -- Take inspiration from the existing [examples](https://github.com/NawaMan/CodingBooth/tree/latest/examples).

## For AI Agents

If you're an AI agent (Claude, Copilot, Cursor, GPT, etc.) helping a user with CodingBooth, read [docs/AGENT_SETUP.md](docs/AGENT_SETUP.md).

## Installation

Run the following on the project **base folder** to install [CodingBooth Wrapper](https://github.com/NawaMan/WorkSpaceWrapper).
The wrapper allows management of the booth script file.

```shell
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
```

Run the wrapper script and follow the instructions.

```shell
./ws
```

### Updating CodingBooth

To update CodingBooth to the latest version:

```shell
# Re-run the wrapper to update the booth script
./ws

# Pull the latest images (optional, happens automatically if not present)
./booth --pull
```

The wrapper script (`./ws`) checks for updates and downloads the latest `coding-booth` binary when run.

## CLI Usage

CodingBooth provides a command-line interface with the following structure:

```shell
./booth [flags] [-- command...]
```

### Common Flags

| Flag               | Description                                                                      |
|--------------------|----------------------------------------------------------------------------------|
| `--variant <name>` | Select container variant (base, notebook, codeserver, desktop-xfce, desktop-kde) |
| `--version <tag>`  | Specify image version tag (default: latest)                                      |
| `--name <name>`    | Set container name                                                               |
| `--port <port>`    | Set host port mapping (number, NEXT, or RANDOM)                                  |
| `--daemon`         | Run container in background                                                      |
| `--pull`           | Force pull latest image                                                          |
| `--dind`           | Enable Docker-in-Docker mode                                                     |
| `--keep-alive`     | Keep container after exit                                                        |
| `--silence-build`  | Suppress build/startup output                                                    |
| `--dryrun`         | Print docker commands without executing                                          |
| `--verbose`        | Enable debug output                                                              |
| `--config <path>`  | Use custom config file                                                           |
| `--code <path>`    | Set code directory                                                               |
| `--help`, `-h`     | Show help information                                                            |

### Examples

```shell
# Start with default settings (interactive shell)
./booth

# Start VS Code in browser
./booth --variant codeserver

# Run a command and exit
./booth -- make test

# Start in background with custom port
./booth --daemon --port 8080

# Dry-run to see what would be executed
./booth --dryrun --verbose
```

## Why CodingBooth?

When developing inside containers, files you create often end up owned by the container’s user (usually `root`).  
This leads to frustrating permission issues on the host — you can’t easily edit, remove, or commit those files without resorting to `sudo` or other workarounds.

**CodingBooth** solves this by mapping the container’s user to **your host UID and GID**.  
That means every file you create or modify inside the container is **owned by you on the host** — just as if it were created directly on your local machine.


### What This Gives You

- **Seamless file access** – Create, edit, and delete files inside the container, then use them on the host with no permission issues.  
- **Team-friendly** – Each developer uses their own UID and GID mapping — no more “root-owned” repositories.  
- **Project isolation** – Keep toolchains and dependencies inside the container while working directly in your project folder.  
- **Portable configuration** – `.booth/config.toml` travel with your repository, ensuring consistent setups across machines.


## Variants

CodingBooth provides several **ready-to-use container variants** designed for different development workflows.
Each variant comes pre-configured with a curated toolset and a consistent runtime environment.

### Available Variants

- **`base`** – A minimal base image with essential shell tools.  
  Ideal for building custom environments, running CLI applications, or lightweight automation tasks.
  The terminal is expose with [ttyd](https://github.com/tsl0922/ttyd) on port 10000.

- **`notebook`** – Includes [Jupyter Notebook](https://jupyter.org/) with Bash and other utilities.  
  Great for data science, analytics, documentation, or interactive scripting workflows.

- **`codeserver`** – A web-based VS Code environment powered by [`code-server`](https://github.com/coder/code-server).  
  Provides a full browser-accessible IDE with Git integration, terminals, and extensions.

- **[`desktop-xfce`]( https://www.xfce.org  )**, **[`desktop-kde`]( https://kde.org/plasma-desktop)** – Full Linux desktop environments accessible via browser or remote desktop (e.g., [noVNC](https://novnc.com)).  
  Useful for GUI-heavy workflows or running native IDEs like [IntelliJ IDEA](https://www.jetbrains.com/idea/), [PyCharm](https://www.jetbrains.com/pycharm/), or [Eclipse](https://www.eclipse.org) inside Docker.

All variants expose its UI on port 10000 but NEXT and RANDOM can be use. See [Port](#6-ports) for more details. 

### Aliases & Defaults

CodingBooth supports several shortcuts and aliases for variant names:

| Input Alias	| Resolved Variant |
|-------------|------------------|
| default	    | base             |
| console     | base             |
| ide	        | codeserver       |
| notebook    | notebook         |
| codeserver  | codeserver       |
| desktop	    | desktop-xfce     |
| xfce        | desktop-xfce     |
| kde	        | desktop-kde      |

If an unknown value is provided, CodingBooth will exit with an error listing supported variants and aliases.

### Desktop Configuration

For desktop variants (`desktop-xfce`, `desktop-kde`), you can customize the screen resolution by setting the `GEOMETRY` environment variable.

**Default:** `1280x800`

**Example (command line):**
```bash
./booth --variant desktop-xfce -e GEOMETRY=1920x1080
```

**Example (in `.booth/config.toml`):**
```toml
run-args = ["-e", "GEOMETRY=1920x1080"]
```

#### noVNC Resize Modes

When accessing the desktop through your browser, noVNC supports different resize modes:

- **`remote`** (default) – Dynamically resizes the remote desktop to match your browser window size. The `GEOMETRY` setting becomes the initial size.
- **`scale`** – Scales the desktop to fit your browser window while maintaining the resolution set by `GEOMETRY`.
- **`off`** – No resizing or scaling; displays the desktop at native resolution (1:1 pixel mapping).

To use a specific resize mode, append `&resize=off` or `&resize=scale` to the noVNC URL:
```
http://localhost:10000/vnc.html?autoconnect=1&host=localhost&port=10000&path=websockify&resize=off
```

> 💡 **Tip:** If you set a specific resolution like `1920x1080`, you may want to use `resize=off` to see it at native resolution, or `resize=scale` to fit it within your browser window.

#### Clipboard Limitations

noVNC does not have direct clipboard integration with your host machine. To copy and paste text between the remote desktop and your host:

1. Click the arrow on the left edge of the screen to open the noVNC side panel
2. Select the clipboard icon
3. Use the text area to transfer clipboard content:
   - **To paste into VNC:** Paste text into the panel, then Ctrl+V inside the desktop
   - **To copy from VNC:** Copy text inside the desktop, then copy from the panel to your host

![Clipboard Panel](noVNC-Clipboard.gif)

### Code Server Notes

#### Clipboard in Terminal

When pasting into the integrated terminal, your browser may show a "Paste" confirmation popup instead of pasting directly. This is a browser security feature for clipboard access. Simply click the popup or press Enter to confirm the paste.

This behavior is inconsistent because it depends on several browser conditions:
- **Clipboard permission granted** — Once allowed, pastes may work directly for that session
- **Terminal has focus** — Clicking directly into the terminal before pasting helps
- **Recent user gesture** — Browsers require recent interaction (click/keypress); paste immediately after clicking and it works, wait too long and the popup appears
- **HTTPS context** — Clipboard API is more reliable over HTTPS; HTTP localhost can be inconsistent

When all conditions align, paste works directly. When any condition isn't met, the confirmation popup appears.

### Typical Use Cases

- **Data Science & Notebooks** – Quickly spin up reproducible Jupyter environments using `--variant notebook`.  
  Ideal for experiments, reports, or teaching interactive examples.

- **Executable Bash Notebooks** – Use `--variant notebook` to work in a Jupyter environment that includes a **Bash kernel**.
  This allows you to write notebooks that mix explanations, commands, and output in one place — effectively turning a notebook into a runnable document.
  It's ideal for creating repeatable build instructions, walkthroughs, tutorials, or Makefile-like automation that is much more readable and approachable than shell scripts alone.

- **Web or App Development** – Develop directly in a browser-based IDE using `--variant codeserver`, complete with terminal and Git integration.

- **Lightweight CLI Workflows** – Use `--variant base` for scripting, building, and testing in an isolated but fast shell environment.

- **GUI Development Environments** – Run full desktop IDEs or graphical tools using `--variant desktop-*`.  
  Perfect for complex projects requiring a windowed environment without polluting your host.

- **Continuous Integration & Training** – Standardize development or CI environments for teams and classrooms, ensuring consistent behavior across machines.

---

> 💡 **Tip:** You can override the variant at runtime using:
> ```bash
> ./booth --variant codeserver
> ```
> Or set it permanently in your configuration file (`.booth/config.toml`).


## Built-in Tools

Every CodingBooth image comes with a carefully selected set of command-line tools for productivity, scripting, and troubleshooting.  
These essentials are preinstalled so you can start working immediately — no extra setup required.

### 🧰 Included Tool Categories

- **Shells & Process Management**  
  `bash`, `zsh`, `tini`

- **Networking & Transfers**  
  `curl`, `wget`, `httpie`

- **Source Control & GitHub Integration**  
  `git`, `gh` (GitHub CLI), `tig`

- **Editors & File Browsers**  
  `nano`, `tilde`, `ranger`, `less`

- **Data Processing & Formatting**  
  `jq`, `yq`, `tree`

- **Compression & Archiving**  
  `unzip`, `zip`, `xz-utils`

- **System Utilities**  
  `ca-certificates`, `locales`, `sudo`

---

> 💡 **Tip:** Each variant extends this base toolset — for example,
> `notebook` adds Jupyter, and `codeserver` adds a web-based IDE.
> You can also customize your setup by adding additional packages in your Dockerfile.

### Available Setup Scripts

CodingBooth provides ready-to-use setup scripts for common development tools. Add them to your `.booth/Dockerfile`:

```dockerfile
FROM nawaman/codingbooth:base-latest

# Languages
RUN python--setup.sh           # Python with pip, venv
RUN nodejs--setup.sh           # Node.js with npm
RUN jdk--setup.sh              # Java JDK
RUN go--setup.sh               # Go language

# Build tools
RUN mvn--setup.sh              # Apache Maven
RUN gradle--setup.sh           # Gradle

# Developer tools
RUN docker-compose--setup.sh   # Docker Compose
RUN neovim--setup.sh           # Neovim editor
```

**To see all available scripts:**
```bash
# Inside a running container
ls /opt/codingbooth/setups/

# Or check the repository
# https://github.com/NawaMan/CodingBooth/tree/main/variants/base/setups
```

> 💡 **Tip:** Setup scripts handle PATH configuration, environment variables, and any required startup hooks automatically.


## Quick Examples

```shell
./booth -- make test
```

```shell
./booth -- 'read -r -p "Press Enter to continue..."'
```

More examples : https://github.com/NawaMan/WorkSpace/tree/main/examples


## Customization

You can tailor how CodingBooth runs by adjusting configuration files or using runtime flags:

- **`.booth/config.toml`** – Defines the image name, variant, UID/GID overrides, and default ports.  
- **Runtime flags** – Options such as `--variant`, `--name`, `--pull`, `--dryrun`, and others can override defaults at launch.

> 💡 **Tip:** Configuration precedence follows this order:  
> **CLI flags → config file → environment variables → built-in defaults.**
> **Bootstrap note:** `--code` and `--config` are evaluated early (CLI first pass or defaults) and are not overridden by environment variables/TOML configuration file.

#### The `.booth/` Folder

All booth configuration lives in a single `.booth/` folder in your project root:

```
my-project/
└── .booth/
    ├── config.toml     # Launcher configuration
    ├── Dockerfile      # Custom Docker build (optional)
    ├── home/           # Team-shared home directory files (optional)
    │   └── .config/
    └── tools/          # Managed by booth wrapper (auto-created)
        └── coding-booth
```

| File | Purpose |
|------|---------|
| `config.toml` | Defines variant, ports, run-args, build-args, cmds |
| `Dockerfile` | Custom image build extending a base variant |
| `home/` | Team-shared dotfiles copied to `/home/coder/` at startup |

> ⚠️ **Note on `cmds`:** When you pass commands via CLI (`-- <cmd>`), they **override** the `cmds` in config.toml (they don't append).

---

## Guarantees & Limits

- ✅ **Host file ownership:** All files in your project folder remain owned by your host user — no "root-owned" files.
- ✅ **Consistent user mapping:** Each container automatically creates a matching user and group via `booth-entry`.
- ⚠️ **Cross-OS caveats:** CodingBooth doesn't abstract away all host OS differences — things like line endings, symlinks, or file attributes may still vary between platforms.

### Security Considerations

CodingBooth is designed for development environments, not production workloads. Key security aspects:

| Aspect | Behavior |
|--------|----------|
| **User privileges** | Processes run as unprivileged `coder` user, not root |
| **Sudo access** | `coder` has passwordless sudo (for installing packages) |
| **File ownership** | Files match your host UID/GID — no root-owned files |
| **Network** | Full network access by default; use Network Whitelist for restrictions |
| **DinD mode** | Requires `--privileged` flag (elevated permissions) |

**Best practices:**
- Don't run untrusted code in CodingBooth containers
- Use Network Whitelist in security-conscious environments
- Avoid mounting sensitive host directories beyond what's needed
- DinD mode grants significant privileges — use only when needed

> ⚠️ **Note:** CodingBooth prioritizes developer experience over strict isolation. For production containers or multi-tenant environments, use standard Docker security practices.

### JetBrains IDE Licensing in Containers

JetBrains activation is stored as a machine-specific token. When you run an IDE backend inside a container, a fresh container may be treated as a new machine, so you may be asked to sign in again unless IDE state is persisted.

**Recommended approaches:**
- **JetBrains Gateway (preferred):** license checked on your local machine; container backend doesn't store license data.
- **Persistent volumes:** mount configs/caches/plugins if you run a full GUI IDE inside the container.
- **License Vault:** for short-lived containers / multi-machine scenarios.

---

## How It Works

1. The launcher passes your **host UID** and **GID** into the container using the environment variables `HOST_UID` and `HOST_GID`.  
2. Inside the container, the entrypoint script (`booth-entry`) ensures a matching `coder` user and group exist with those IDs.  
3. The directories `/home/coder` and `/home/coder/code` are owned by that user, ensuring smooth file sharing between host and container.  
4. Add the user `coder` to sudoers so that it can sudo without needing the password
5. Prepare `.bashrc` and `.zshrc`
6. Run startup script (files in `/etc/startup.d`)
7. All commands run as the unprivileged **`coder`** user, not `cdroot`, preserving security and consistent file ownership.


```
host                                 # your machine
  ├── project/                       # your project folder on the host
  |    ├── booth                     # booth wrapper script
  |    ├── .booth                    # booth internal folder
  |    |    ├── tools                # booth tools folder
  |    |        └── coding-booth     # booth runner script
  |    ├── ...                       # other project files
  ...

container
  ├── home/
  |    ├── coder/
  |    |    ├── code/                     # your project folder inside the container
  |    |    |   ├── booth                 # booth wrapper script
  |    |    |   ├── .booth                # booth internal folder
  |    |    |   |    ├── tools            # booth tools folder
  |    |    |   |    └── coding-booth     # booth runner script
  |    |    ├── ...                       # other project files
  |    ├── ...                            # other home files
  ├── etc/
  |    ├── profile.d/                     # profile script folder
  ├── opt/
  |    ├── coding-booth/
  |    |    ├── setups/                   # setup script folder
  |    |    |    ├── ...                  # setup scripts
  ├── usr/
  |    ├── local/
  |    |    ├── bin/                      # program file folder
  |    ├── share/
  |    |    ├── startup.d/                # startup script folder
  ...
```

---

> 🧠 **In short:**
> CodingBooth mirrors your host identity inside the container — you work as yourself, not as root.


**Result:** seamless dev environment, no permission headaches.

### Data Persistence

Understanding what persists across container restarts is critical:

| Location | Persists? | Notes |
|----------|-----------|-------|
| `/home/coder/code/` | **Yes** | Bind-mounted from host; this is your project folder |
| `/home/coder/` (outside `code/`) | No | Ephemeral; lost on container restart |
| `/opt/`, `/usr/`, `/etc/` | No | System directories; lost on restart |
| Installed packages | No | Must be in Dockerfile to persist |

**What this means:**
- **Your code is safe** — it lives on the host and is never lost
- **Home directory customizations** — use `.booth/home/` or `.booth/home-seed/` to persist dotfiles
- **Installed tools** — add them to your `.booth/Dockerfile` so they're rebuilt each time
- **Container state** — treat containers as disposable; rebuild rather than modify

> 💡 **Tip:** If you need to persist something outside `/home/coder/code/`, either add it to your Dockerfile or mount an additional volume via `run-args`.

---

> 📝 **Technical Note:**
> CodingBooth uses the Docker CLI (`docker` command) rather than Docker client libraries.
> This keeps the codebase simple, portable, and easier to maintain while ensuring compatibility across platforms.

### In-Container Documentation

Every CodingBooth container includes documentation and resources at `/opt/codingbooth/`:

```
/opt/codingbooth/
├── README.md              # This documentation
├── LICENSE                # Apache 2.0 License
├── version.txt            # Current CodingBooth version
├── AGENT.md               # Instructions for AI agents
├── variants/              # Dockerfiles for all variants
│   ├── base/Dockerfile
│   ├── codeserver/Dockerfile
│   └── ...
└── setups/                # Built-in setup scripts
    ├── python--setup.sh
    ├── node--setup.sh
    └── ...
```

Run `codingbooth-info` inside the container to see a quick overview of your environment.

#### For AI Agents

If you're using an AI coding assistant inside a CodingBooth container, the agent can find instructions at:

- `/opt/codingbooth/AGENT.md` — the canonical location

This file provides operational instructions specifically for AI agents working inside the container — covering persistence rules, setup patterns, and how to properly configure the environment.

**Optional:** Create a symlink in the home directory so your AI agent discovers it automatically. Add to `.booth/startup.sh`:

```bash
# Link for your AI agent (choose the one you use)
ln -sf /opt/codingbooth/AGENT.md /home/coder/CLAUDE.md      # Anthropic Claude
ln -sf /opt/codingbooth/AGENT.md /home/coder/COPILOT.md     # GitHub Copilot
ln -sf /opt/codingbooth/AGENT.md /home/coder/CURSOR.md      # Cursor IDE
ln -sf /opt/codingbooth/AGENT.md /home/coder/GPT.md         # OpenAI GPT/ChatGPT
ln -sf /opt/codingbooth/AGENT.md /home/coder/GEMINI.md      # Google Gemini
ln -sf /opt/codingbooth/AGENT.md /home/coder/CODEIUM.md     # Codeium/Windsurf
ln -sf /opt/codingbooth/AGENT.md /home/coder/WARP.md        # Warp terminal
```

### Home Directory Customization

CodingBooth provides mechanisms for populating the user's home directory with custom files at container startup. There are two patterns: **seed** (no-clobber) and **override**.

#### Project Home Seed (`.booth/home-seed/`)

Create a `.booth/home-seed/` folder in your project to provide team-wide defaults that **will not overwrite** existing files.

**How it works:**
- Place files in `.booth/home-seed/` with the same structure as `$HOME`.
- At container startup, files are copied to `/home/coder/` **without overwriting** existing files.
- Good for providing default templates that users can customize.

#### Project Home Override (`.booth/home/`)

Create a `.booth/home/` folder in your project to provide team-wide configs that **will overwrite** existing files.

**How it works:**
- Place files in `.booth/home/` with the same structure as `$HOME`.
- At container startup, files are copied to `/home/coder/` **overwriting** existing files.
- Good for enforcing consistent team configurations.

**Example structure:**
```
my-project/
├── .booth/config.toml
├── .booth/Dockerfile
├── .booth/home-seed/        # Defaults (won't overwrite)
│   └── .config/
│       └── myapp/
│           └── config.yaml  # Default config template
└── .booth/home/             # Overrides (will overwrite)
    ├── .bashrc              # Team bashrc (enforced)
    └── .gitconfig           # Team git settings (enforced)
```

> ⚠️ **Warning:**
> Do NOT put secrets, credentials, or personal tokens in `.booth/home/` or `.booth/home-seed/` — these folders are meant to be committed to version control and shared with your team.

#### Host Home Seed (`/etc/cb-home-seed/`)

Mount host files read-only to `/etc/cb-home-seed/` for **personal credentials** that should not be version-controlled.

**How it works:**
1. Mount host files read-only to `/etc/cb-home-seed/` (preserving the relative path structure)
2. At container startup, files are copied to `/home/coder/` **without overwriting** existing files
3. The user gets a writable copy; the host's original files stay protected

#### Host Home Override (`/etc/cb-home/`)

Mount host files read-only to `/etc/cb-home/` for **personal configs** that should override other sources.

**How it works:**
1. Mount host files read-only to `/etc/cb-home/` (preserving the relative path structure)
2. At container startup, files are copied to `/home/coder/` **overwriting** existing files

**Example (`.booth/config.toml`):**
```toml
run-args = [
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",
    "-v", "~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro"
]
```

**Use cases:**
- **Credentials** — gcloud, GitHub Copilot, SSH keys (apps may refresh tokens)
- **Personal IDE settings** — VS Code, IntelliJ configurations
- **Personal dotfiles** — `.bashrc`, `.gitconfig` customizations

#### Precedence Order

Files are copied in this order:

1. **`.booth/home-seed/`** (project folder) — Team defaults, no-clobber
2. **`.booth/home/`** (project folder) — Team overrides, will overwrite
3. **`/etc/cb-home-seed/`** (host mounts) — Personal defaults, no-clobber
4. **`/etc/cb-home/`** (host mounts) — Personal overrides, will overwrite

The **seed** sources use `cp -rn` (no-clobber) — they only copy if the file doesn't exist.
The **override** sources use `cp -r` — they always copy, overwriting existing files.

> 💡 **Tip:**
> Use **seed** for fallback defaults — "if no setup script provided this file, use this one."
> Use **override** for enforced configs — "regardless of what's already there, always use this file."

#### Common Credential Seeding Examples

Here are common credentials you might want to seed from your host:

```toml
# .booth/config.toml
run-args = [
    # Git credentials and config
    "-v", "~/.gitconfig:/etc/cb-home-seed/.gitconfig:ro",
    "-v", "~/.git-credentials:/etc/cb-home-seed/.git-credentials:ro",

    # SSH keys (for git over SSH)
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro",

    # AWS CLI credentials
    "-v", "~/.aws:/etc/cb-home-seed/.aws:ro",

    # Google Cloud credentials
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",

    # Azure CLI credentials
    "-v", "~/.azure:/etc/cb-home-seed/.azure:ro",

    # GitHub CLI
    "-v", "~/.config/gh:/etc/cb-home-seed/.config/gh:ro",

    # GitHub Copilot
    "-v", "~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro",

    # Claude Code
    "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",
    "-v", "~/.claude:/etc/cb-home-seed/.claude:ro",

    # Neovim config
    "-v", "~/.config/nvim:/etc/cb-home-seed/.config/nvim:ro",
    "-v", "~/.local/share/nvim:/etc/cb-home-seed/.local/share/nvim:ro"
]
```

> 💡 **Tip:** Only include the credentials you actually need. Each mount adds startup overhead.

#### Why You Shouldn't Seed Everything

It's tempting to mount your entire `~/.config` or even `~` into the container. **Don't.**

**It defeats the purpose of containers.** The whole point of CodingBooth is a clean, reproducible environment. Bringing too much host state recreates the "works on my machine" problem you're trying to escape.

**Version and architecture conflicts.** Your host's Neovim plugins might be compiled for a different glibc. Your IDE settings might reference paths that don't exist in the container. Your shell config might source files that aren't there.

**Security exposure.** Your home directory contains more secrets than you remember — browser cookies, chat history, cached tokens in random dotfiles, SSH keys you forgot about. Every bind mount increases your attack surface.

**State confusion.** `cb-home-seed` *copies* files at startup (it doesn't sync). You might edit config in the container thinking it persists to host, or edit on host thinking the container will see it. Neither happens.

**Breaks team reproducibility.** If everyone seeds different things, environments diverge. When a new team member joins, they can't reproduce the issues you're seeing.

**Debugging becomes harder.** When something breaks, is it the container image, or something you seeded from host? The more you seed, the harder it is to isolate problems.

**The philosophy:** Seed the *minimum* credentials needed for your specific workflow. Authentication tokens, SSH keys for git, cloud CLI credentials — yes. Your entire dotfile collection — no.

> 🤔 **Reality check:** If you find yourself needing to seed most of your home directory, ask yourself: do you actually need a container? Maybe the friction is telling you something.


## booth Manual

### Feature List

### 1. Image Selection

**Defaults**
- **Repository:** `nawaman/codingbooth`  
- **Variant:** `base`  
- **Version:** `latest`

**Overrides**
- **Environment variables:** `IMAGE_NAME`, `IMAGE_REPO`, `IMAGE_TAG`, `VARIANT`, `VERSION`  
- **Configuration file:** `.booth/config.toml`  
- **CLI options:** `--variant`, `--version`, `--image`, `--dockerfile`

**Precedence**
Command-line arguments → config file → environment variables → built-in defaults

> **Bootstrap note:** `--code` and `--config` are resolved from CLI (first pass) or defaults, and are not overridden by the config file or environment variables.


**Derived Values**
- `IMAGE_NAME` = `IMAGE_REPO:IMAGE_TAG`  
- `IMAGE_TAG` = defaults to `${VARIANT}-${VERSION}`  

> 💡 **Tip:**  
> When both `--image` and `--dockerfile` are provided, `--image` takes precedence.  
> Use `--dockerfile` when you want to build locally; otherwise, CodingBooth automatically pulls prebuilt images from `nawaman/codingbooth`.


### 2. Container Name

**Default**  
- The container name defaults to a sanitized version of the current folder name.  
  If the directory name cannot be determined, it falls back to `booth`.

**Overrides**
- **Environment variable:** `CONTAINER_NAME`  
- **Configuration file:** `.booth/config.toml`  
- **CLI option:** `--name <name>`

---

> 💡 **Tip:**  
> Using unique container names helps avoid conflicts when running multiple booth instances simultaneously.


### 3. Config Files

CodingBooth supports several configuration files that control how containers are built and launched.  
These files let you define defaults, environment variables, and runtime parameters without cluttering your CLI commands.

#### **Launcher Config (`.booth/config.toml`)**
- Loaded after bootstrap flags are determined (`--code`, `--config`) and before full CLI parsing.
- Defines default values for image selection, user mapping, and runtime behavior.
- Typical keys include:
  `variant`, `version`, `image`, `dockerfile`,
  `name`, `host-uid`, `host-gid`, `port`, `dind`, and others.

##### **Custom Argument Arrays**
You can define three special arrays in `.booth/config.toml` to customize how the launcher interacts with Docker:

- **`common-args`** – Pre-applied CLI flags merged before command-line parameters.
  Useful for predefining commonly used options (e.g., extra ports or mounts).
  ```toml
  common-args = ["--variant", "codeserver", "--port", "8080"]
  ```

These behave exactly like command-line flags passed to booth.

- **`build-args`** – Extra args for `docker build` when dockerfile is used.
  For example, disable caching or pass build-time variables:
  ```toml
  build-args = ["--no-cache", "--build-arg", "NODE_VERSION=20"]
  ```
- **`run-args`** – Extra args for `docker run`.
  These are appended automatically at launch:
  ```toml
  run-args = ["-e", "TZ=Asia/Bangkok", "-v", "/mnt/data:/data"]
  ```
- **`cmds`** – Default command to run inside the container.
  Note: CLI `-- <cmd>` overrides this (does not append):
  ```toml
  cmds = ["bash", "-lc", "make test"]
  ```

> 💡 Tip:
> These arrays allow you to version-control useful runtime and build options without hardcoding them into your CLI workflow.
> Combined with `common-args`, you can achieve fully reproducible builds and launches with zero manual typing.

#### Container Environment File (.env)
- Passed directly to Docker using the `--env-file` option.
- Commonly used for credentials or runtime configuration such as: `PASSWORD`, `JUPYTER_TOKEN`, `TZ`, `PROXY`, `ACB_*`, `GH_TOKEN`, etc.
- Can be overridden with `env-file = "<path>"` in config.toml.
- To disable, set `env-file = "none"` in config.toml.

> 🧩 Summary:
> Configuration layers allow customization at two levels:
> Build+Image: .booth/config.toml (persistent project defaults)
> Container Environment: .env (runtime secrets and environment variables)
> Together, they give you full control over build, run, and launcher behavior.


### 4. Host UID/GID Handling

CodingBooth ensures that all files created inside the container are owned by the same user and group as on your host system.  
This eliminates the common “root-owned files” problem when developing inside Docker.

**Defaults**
- Automatically detects and uses your current user and group IDs:
  ```bash
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  ```

### 5. Run Modes

CodingBooth supports multiple run modes to fit different workflows — from one-off commands to long-running containers.

#### **Interactive Shell (Default)**
- Launches an interactive terminal session inside the container.  
- The container is removed automatically when you exit.
  ```bash
  docker run --rm -it ... $IMAGE_NAME
  ```
- Ideal for local development, testing, or exploratory use.

#### Command Mode (-- <cmd>)
- Executes a specific command inside the container and then exits.
- Commands are run under a login shell for a consistent environment:
  ```bash
  ./booth -- echo "Hello from container"
  ```
- **Exit code forwarding:** When a command fails, booth silently exits with the same exit code as the command — no error message is printed. This makes booth behave like a transparent wrapper, ideal for scripting and CI/CD pipelines where you want to check `$?` or let the pipeline fail naturally.
  ```bash
  ./booth -- false
  echo $?  # prints: 1
  ```
- Useful for automation, scripting, or CI/CD pipelines.

#### Silent Mode (--silence-build)
- Suppresses container startup messages for a cleaner output.
- Ideal when you want commands to appear as if they're running locally:
  ```bash
  ./booth --variant base --silence-build -- echo "Hello"
  # Output: Hello
  ```
- Combine with command mode to integrate booth commands into scripts or pipelines where only the command output matters.

> ⚠️ **Note:**  
> Silent mode only hides startup messages — the container still needs time to build (if using a custom Dockerfile) and start up.  
> First runs or cold starts may take several seconds to minutes depending on image pull/build requirements.
  
#### Daemon Mode (--daemon)
- Starts the container in the background (detached).
- For the container variant, the container runs an infinite sleep loop to stay alive.
- Commonly used for IDE variants (like codeserver or desktop-*) that provide persistent services.

> 💡 **Tip:**  
> In daemon mode, you can later attach to the container using:
> `docker exec -it <container_name> bash`
> Stop it with:
> `docker stop <container_name>`

### 6. Ports
CodingBooth automatically manages host ↔ container port mappings for interactive and web-based variants.

**Defaults Behavior**
For the notebook and codeserver variants, the container exposes port 10000
- If 10000 is not available, it will try 10001, then 10002, and so on.

**Overrides**
- You can customize the exposed port via:
  - Environment variable: CB_PORT
  - Configuration file: .booth/config.toml
  - CLI flag: --port <number>
- The value can beL:
  - a fixed number (8080), or
  - NEXT (to find the next available port -- 1000 increment), or
  - RANDOM (to assign a random open port -- 1000 increment from 10000).

> 💡 Tip:
> When using multiple booth containers at once, consider setting CB_PORT=NEXT to avoid conflicts automatically.

### 7. Pulling Images

CodingBooth manages Docker image retrieval intelligently to balance performance and consistency.

**Default Behavior**
- If the specified image does not exist locally, CodingBooth will **automatically pull** it from the configured repository.  
- If the image is already present, it reuses the local copy for faster startup.

**Forced Pull**
- Use the `--pull` flag to explicitly fetch the latest image version, even if a local copy exists:
  ```bash
  ./booth --pull
  ```
> 💡 Tip:
> Use --pull periodically to ensure your local environment stays in sync with the latest base image, especially when sharing configurations across teams.


### 8. Dry-Run Mode

The **dry-run** mode allows you to preview exactly what CodingBooth will execute — without actually starting a container.

**Usage**
```bash
./booth --dryrun
```

**Behavior**
- Prints the fully assembled docker run ... command that would be executed.
- No side effects — it does not check Docker status, pull images, or create containers.
- Useful for debugging configuration issues or verifying CLI overrides before launch.

> 💡 Tip:
> Combine --dryrun with --verbose to see detailed variable expansion and runtime configuration.

### 9. Keep Alive
Keep the container around after it stop.
- By default, once the container stop, it will be removed.
- By using `--keep-alive`, the container will be kept around.
- User can re-start the container using: `docker start <container-name>`.
- To remove the **stop** container use: `docker rm <container-name>`.
- To save the current state of a container as a new image:
  ```bash
  docker commit <container-name> <new-image-name>:<tag>
  ```
  > Useful if you made changes inside the container and want to keep them for future use.
- To save an image to a file (for backup or sharing):
  ```bash
  docker save -o <file-name>.tar <image-name>:<tag>
  ```
  > Example: `docker save -o myapp.tar my-image:v1`
- To load a previously saved image file:
  ```bash
  docker load -i <file-name>.tar
  ```
- To export a container’s filesystem as a .tar file:
  ```bash
  docker export -o <file-name>.tar <container-name>
  ```
  > This saves the filesystem only (no image metadata or history).
- To import the exported container back as a new image:
  ```bash
  cat <file-name>.tar | docker import - <new-image-name>:<tag>
  ```
- There are more things you can do with stopped containers, please consult docker documentation for more information.

### 10. Help

Displays detailed usage information, supported flags, and configuration notes.

**Usage**
```bash
./booth --help
# or
./booth -h
```

**Behavior**
- Prints a full help summary including available variants, runtime options, and examples.
- Provides hints for environment variables and configuration file structure.
- Exits immediately after displaying help.

### 11. Docker-in-Docker (DinD) Support

CodingBooth supports **Docker-in-Docker (DinD)** mode, allowing you to build and run Docker containers **from inside your booth container**.  
This feature is useful for CI/CD pipelines, containerized builds, or development environments that need access to Docker tooling.

---

**Behavior**
- When DinD mode is enabled, the booth container gains access to the host’s Docker daemon or runs its own isolated Docker service.  
- The mode can operate in one of two styles:
  1. **Socket sharing (default):** Mounts the host's Docker socket (`/var/run/docker.sock`) for direct access.
  2. **Sidecar DinD service:** Starts a secondary "sidecar" container running the Docker daemon itself.

---

**How It Works (Sidecar Mode)**

When DinD is enabled with the sidecar approach, the launcher:

1. **Creates a dedicated network** — `{container-name}-{port}-dind-net`
2. **Starts a DinD sidecar** — A `docker:dind` container runs the Docker daemon
3. **Shares network namespace** — The booth uses `--network container:{dind}` so `localhost` refers to the sidecar
4. **Configures Docker access** — Sets `DOCKER_HOST=tcp://localhost:2375`

```
Host
└── Docker
    ├── DinD sidecar container
    │   └── Docker daemon (:2375)
    │       └── (your containers run here)
    └── Booth container
        ├── shares DinD's network (localhost = DinD)
        └── DOCKER_HOST=tcp://localhost:2375
```

This allows the booth to run Docker commands that execute inside the isolated DinD environment.

---

**Configuration**
- Enable DinD by setting:
  ```bash
  DIND=true
  ```
  in your .booth/config.toml file or by passing:
  ```bash
  ./booth --dind
  ```
- Default behavior (DIND=false) disables Docker access inside the container.
  
**Usage Notes**
- DinD mode may increase resource usage and startup time.
- The sidecar approach offers stronger isolation but can be slower and more complex to manage.

> 💡 **Tip:**
> See `examples/dind-example` for basic DinD usage, or `examples/kind-example` for running Kubernetes with KinD inside the booth.


### 12. Network Whitelist

CodingBooth includes a **network whitelist** feature that restricts container internet access to only approved domains. This is useful for:
- Security-conscious environments
- Ensuring containers only access package registries
- Compliance requirements that limit network access

**How It Works**
- Uses a lightweight HTTP proxy (tinyproxy) inside the container
- Only allows connections to whitelisted domains
- Disabled by default for backwards compatibility

**Enabling Network Whitelist**

First, include the setup in your Dockerfile:
```dockerfile
RUN /opt/codingbooth/setups/network-whitelist--setup.sh
```

Then enable it inside the container:
```bash
network-whitelist-enable
```

**Default Whitelisted Domains**

The following package registries and services are whitelisted by default:
- **npm:** registry.npmjs.org, npmjs.com, yarnpkg.com
- **Python:** pypi.org, files.pythonhosted.org
- **Maven:** repo.maven.apache.org, repo1.maven.org
- **Go:** proxy.golang.org, sum.golang.org
- **Rust:** crates.io, static.crates.io
- **Docker:** registry-1.docker.io, docker.io
- **GitHub:** github.com, raw.githubusercontent.com
- **Ubuntu/Debian:** archive.ubuntu.com, security.ubuntu.com

**Adding Custom Domains**

Option 1: Using the CLI command
```bash
network-whitelist-add example.com api.example.com
network-whitelist-reload
```

Option 2: Edit the whitelist file directly
```bash
# Edit ~/.network-whitelist (one domain per line)
nano ~/.network-whitelist
network-whitelist-reload
```

Option 3: Team-shared whitelist via `.booth/home/`
```
my-project/
└── .booth/
    └── home/
        └── .network-whitelist    # Team-shared custom domains
```

**Available Commands**

| Command                    | Description                              |
|:---------------------------|:-----------------------------------------|
| `network-whitelist-enable` | Enable network restrictions              |
| `network-whitelist-disable`| Disable network restrictions             |
| `network-whitelist-status` | Show current status and domain counts    |
| `network-whitelist-list`   | List all whitelisted domains             |
| `network-whitelist-add`    | Add domain(s) to user whitelist          |
| `network-whitelist-reload` | Apply whitelist changes                  |

> ⚠️ **Note:**
> The network whitelist only affects HTTP/HTTPS traffic that respects proxy environment variables.
> Most package managers (npm, pip, maven, etc.) respect these variables automatically.

For detailed documentation including the full default whitelist, troubleshooting, and file locations, see [docs/URL_WHITELIST.md](docs/URL_WHITELIST.md).


## Setup Implementation Notes
Setup scripts are scripts that install tools and dependencies.
Not every tool or dependency needs a setup script.
A basic `apt-get install ....` or `curl ...` can be be used.
A setup script may be required, if a tool or dependency requires:
- user specific configuration
- custom bash session (such as environmental variables)
- a starter wrapper
- requires other tools or dependencies that need a setup script.

### Setup Files Overview

CodingBooth setup scripts follow a simple pattern that produces **three artifacts**:

1. **Startup script** (runs once per container start, as the normal user)  
   - Path: `/usr/share/startup.d/<LEVEL>-cb-<thing>--startup.sh`  
   - Purpose: one-time initialization per container boot (idempotent).  
   - Example tasks: create user cache dirs, generate config files if missing, first-run migrations.

2. **Profile script** (sourced at the beginning of every shell session)  
   - Path: `/etc/profile.d/<LEVEL>-cb-<thing>--profile.sh`  
   - Purpose: lightweight per-shell setup.  
   - Example tasks: export env vars, update `PATH`, define aliases.

3. **Starter wrapper** (a user-invoked command wrapper)  
   - Path: `/usr/local/bin/<thing>`  
   - Purpose: pre-/post-steps around the real tool, then `exec` the tool.  apt
   - Example tasks: set tool-specific env, ensure background service is running, sanitize args.

> 🧩 **From the template**  
> - Replace `XXXXXX` with your feature/tool name (e.g., `python`, `codeserver`).  
> - Adjust `LEVEL` (see **Profile Ordering** below).  
> - Use `envsubst` placeholders (e.g., `$XXXXXX_VERSION`) to stamp values into generated files.  
> - Make startup/profile code **idempotent** (safe to run multiple times).

---

### Startup/Profile Ordering

Name your scripts using this pattern:  
`/etc/profile.d/<LEVEL>-cb-<thing>--profile.sh` and `/etc/startup.d/<LEVEL>-cb-<thing>--startup.sh`

Choose `<LEVEL>` from these ranges to keep load order predictable:

| Level Range | Purpose                                                               |
|-------------|-----------------------------------------------------------------------|
| **50–54**   | Core CodingBooth base setup                                           |
| **55–59**   | OS / UI setup (desktop, display, browsers)                            |
| **60–64**   | Language / platform setup (Python, Java, Node.js, Go, etc.)           |
| **65–69**   | Language / platform extensions (venv managers, JDK tools, linters)    |
| **70–74**   | Developer tools (IDEs, editors, notebook servers)                     |
| **75–79**   | Tool extensions (plugins, kernels, IDE extensions)                    |

> 💡 **Guideline:** Prefer **lower** levels for prerequisites and **higher** levels for dependents.  
> For example, install Python at **60–64**, then add Jupyter kernels at **75–79**.

---

### Setup Pattern & Conventions

**Script naming**
- Installation script (run as root): `*setup.sh` (placed in a build or image layer)
- Generated files (by the setup script):  
  - Startup: `/etc/startup.d/<LEVEL>-cb-<thing>--startup.sh`  
  - Profile: `/etc/profile.d/<LEVEL>-cb-<thing>--profile.sh`  
  - Starter: `/usr/local/bin/<thing>`

**Root vs. user**
- The *setup script itself* runs as **root** (installs packages, writes system files).  
- **Startup** and **profile** scripts run as the **normal user** at container start or shell login, respectively.

**Idempotence**
- Startup/profile code must be safe to run multiple times.  
- Use a sentinel when needed:
  ```bash
  SENTINEL="$HOME/.<thing>-startup-done"
  [[ -f "$SENTINEL" ]] && exit 0
  touch "$SENTINEL"

**Environment variables**
- Prefer the CB_* prefix for CodingBooth-specific variables (e.g., CB_PYTHON_HOME).
- In profile scripts, keep exports lightweight and guarded:
  ```bash
  case ":$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:$PATH";; esac
  ```

**Starter wrappers**
- Keep wrapper logic minimal and exec the real binary:
```bash
# /usr/local/bin/<thing>
# pre-steps...
exec /usr/local/bin/real-<thing> "$@"
```
- Exit non-zero on failure; avoid swallowing errors.

**File permissions**
- Startup: chmod 755
- Profile: chmod 644
- Starter: chmod 755

## Custom Setups
You can create your own setup scripts to install any tool you need.
Simply copy into your docker image and run it just like other setup scripts.


## Troubleshooting

### "Docker not found" or "Cannot connect to Docker daemon"

```bash
# Check if Docker is installed and running
docker version

# If permission denied, add yourself to docker group
sudo usermod -aG docker $USER
# Then logout and login again
```

### "Permission denied" on project files

This usually means the container's user doesn't match your host user. CodingBooth handles this automatically, but if you see issues:

```bash
# Check your UID/GID
id

# Verify booth is passing them correctly
./booth --dryrun --verbose | grep HOST_UID
```

### "Port already in use"

```bash
# Find what's using the port
lsof -i :10000

# Use a different port
./booth --port 10001

# Or let CodingBooth find the next available port
./booth --port NEXT
```

### "Container exits immediately"

Common causes:
- **Command failed** — Check the exit code and logs
- **Missing dependencies** — Ensure your Dockerfile installs everything needed
- **Syntax error in startup script** — Check `.booth/startup.sh`

```bash
# Debug by getting a shell instead
./booth --variant base

# Check container logs
docker logs <container-name>
```

### "Build takes forever" / "Downloading same packages every time"

Your Dockerfile might not be using layer caching effectively:
- Put rarely-changing commands first
- Use `COPY requirements.txt` before `RUN pip install`
- Don't run `apt-get update` and `apt-get install` in separate layers

### Desktop variant shows black screen

- Wait a few seconds — VNC server takes time to start
- Check `~/.vnc/*.log` inside the container for errors
- Verify dbus is running: `pgrep dbus-daemon`

### "Network timeout" when installing packages

If behind a corporate proxy:
```toml
# .booth/config.toml
run-args = [
    "-e", "HTTP_PROXY=http://proxy.company.com:8080",
    "-e", "HTTPS_PROXY=http://proxy.company.com:8080"
]
```

### Still stuck?

1. Try `--verbose` for detailed debug output
2. Use `--dryrun` to see the exact Docker command
3. Check [GitHub Issues](https://github.com/NawaMan/CodingBooth/issues) for similar problems
4. Open a new issue with your config and error message


## Implementation Documentation

For deeper technical details on how CodingBooth works internally, see [docs/implementations/](docs/implementations/):

- **[User Permissions](docs/implementations/USER_PERMISSIONS.md)** — UID/GID mapping between host and container
- **[Desktop + noVNC](docs/implementations/DESKTOP_NOVNC.md)** — VNC server and browser-based desktop access
- **[Variant Selection](docs/implementations/VARIANTS.md)** — How variants and aliases are resolved
- **[Docker-in-Docker](docs/implementations/DIND.md)** — Running Docker inside CodingBooth
- **[Network Whitelist](docs/implementations/URL_WHITELIST.md)** — Restricting container network access


## Community & Feedback

CodingBooth is built to meet **real developer needs** — simple, reproducible, and flexible without unnecessary complexity.  
Your feedback and contributions help it evolve and stay relevant for everyone.

---

### 🐛 Issues & Contributions
- Use the **[Issues page](../../issues)** to report bugs, request new features, or suggest improvements.  
- Pull Requests are always welcome — from fixing typos to adding new setup scripts or container variants.  
- Have a creative idea, workflow, or enhancement to share? Open an issue or discussion — we’d love to hear it.  
- Prefer to reach out directly? Feel free to contact me through any of the links below.

---

### ☕ Support & Appreciation
If CodingBooth has saved you time, simplified your setup, or made development more enjoyable —  
you can **[buy me a coffee](https://buymeacoffee.com/NawaMan)** to show your support.  

Your encouragement keeps this project active — and might even help with my kids’ college fund 😄.

---

### 🌐 Connect
Stay in touch or follow updates, insights, and development notes:
- 🐦 Twitter/X: [@nawaman](https://x.com/nawaman)
- 💼 LinkedIn: [nawaman](https://www.linkedin.com/in/nawaman/)
- 📰 Blog: [nawaman.net/blog](https://nawaman.net/blog/)

---

> 🙏 Every issue, idea, and pull request — big or small — helps make CodingBooth better for everyone.  
> Thank you for being part of the community!





