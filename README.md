# CodingBooth

**Current Version:** v0.28.0 — [View Changelog](docs/CHANGELOG.md)

![Works On My Machine](docs/Works-On-My-Machine-small.png)

**CodingBooth** delivers fully reproducible, isolated development environments — anywhere, on any machine.

You’ve containerized your app. You’ve containerized your build.
But your development environment? Still a mess of system-wide installs, mismatched versions, and onboarding docs no one reads?

**CodingBooth fixes that.**

Run a browser-based VS Code workspace, a Jupyter notebook, or even an entire Linux desktop inside a container — with every file owned by you, not root. Your environment lives with the project. **Launching a single command**, and works with the code on every machine.

New teammate joining? Restart the work on a project after months? Running one command and get the exact same environment.
No setup guides. No dependency drift. No “works on my machine.”

Zero-setup onboarding, portable development environments, and a clean, consistent workspace that just works!


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
- **Pre-configured convenience** - multiple pre-configured setups and variants that are ready to use. 


## Who Should Use CodingBooth?

CodingBooth provides reproducible, zero-friction development environments for:

- **Development Teams**: Share identical setups to eliminate "works on my machine" issues and onboard instantly.
- **Multi-Project Developers**: Isolate project dependencies in containers to prevent cross-contamination.
- **Educators and Students**: Distribute uniform environments so everyone can focus on learning, not troubleshooting installations.
- **Researchers and Academics**: Pause and resume work months later with guaranteed environment consistency—no rebuilding necessary.
- **Solo Developers and Hobbyists**: Create portable, self-contained workspaces that run anywhere without bloating your host system.

Ready to try it? Check out the [Quick Try](#quick-try) section!


## Quick Demo

[![Demo](docs/images/CodingBooth-Demo-Preview.gif)](https://youtu.be/Rvv3UcOqv3c)

Click the image to watch the demo.

In this demo, you can modify/build a snake game using zig, run it inside the container and use the cross-platform binary on the host without having zig toolchain installed on the host.

### Variants

CodingBooth supports multiple variants — different UIs that share the same underlying environment.

- **Base** — A minimal terminal session.
- **Notebook** — Jupyter Lab with multi-language kernels (Python, Bash, Java, and more). 
- **Code Server** — VS Code running in your browser with full extension support.
- **XFCE Desktop** — A full Linux desktop accessible via your browser. 
- **KDE Desktop** — A feature-rich Linux desktop with KDE Plasma.
- **Command passthrough** — Skip the UI entirely. Run any command inside the container with booth `-- <command>` and get the result directly in your terminal.


#### Example Screenshots

| Base                                                                          | Bash                                                                                 |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![Base](docs/images/Booth-Base.png)](docs/images/Booth-Base.png)             | [![Bash](docs/images/Booth-Bash.png)](docs/images/Booth-Bash.png)                    |
| `booth --variant base`                                                        | `booth -- bash`                                                                      |

| Notebook                                                                      | Code Server                                                                          |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![Notebook](docs/images/Booth-NoteBook.png)](docs/images/Booth-NoteBook.png) | [![Code Server](docs/images/Booth-CodeServer.png)](docs/images/Booth-CodeServer.png) | 
| `booth --variant notebook`                                                    | | `booth --variant codeserver`                                                       |

| XFCE Desktop                                                                  | KDE Desktop                                                                          |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![XFCE](docs/images/Booth-XFCE.png)](docs/images/Booth-XFCE.png)             | [![KDE](docs/images/Booth-KDE.png)](docs/images/Booth-KDE.png)                       | 
| `booth --variant desktop-xfce`                                                | `booth --variant desktop-kde`                                                        | 


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
- [Boothfile](#boothfile)
- [Guarantees & Limits](#guarantees--limits)
- [How It Works](#how-it-works)
- [`booth run` Reference](#booth-run-reference)
- [Setup Implementation Notes](#setup-implementation-notes)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)
- [Developer Setup](#developer-setup)
- [Community & Feedback](#community--feedback)


## Quick Try

### Try with an example

CodingBooth provides several ready to use examples to get you started.

1. **Install CodingBooth**:
   ```bash
   curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash \
       ./booth install \
       ./booth shell-config
   ```

2. **List available examples**:
   ```bash
   ./booth example list
   ```

3. **Try an example**:
   ```bash
   ./booth example try <example-name> <folder>
   ```

4. **Start the booth**:
   ```bash
   cd <folder>
   ./booth
   ```

At this point, you can inspect the code, modify it then build and run it.


### Try with an init

CodingBooth provides `init` and `template` commands to quickly create a new project.

1. **Install CodingBooth**:
   ```bash
   curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash \
       ./booth install \
       ./booth shell-config
   ```

2 **List templates**
   ```bash
   ./booth template list
   ```
   or
   ```bash
   ./booth template list --full
   ```
   These would show you the available templates/extensions.

3. **Create a new project**:
   ```bash
   ./booth init <project-name> --select templates
   ```

4. **Start the booth**:
   ```bash
   cd <project-name>
   ./booth
   ```

Explore more with:

```bash
./booth template help
./booth init help
```


## Installation

Run the following on the project **base folder** to install [CodingBooth Wrapper](https://github.com/NawaMan/WorkSpaceWrapper).
The wrapper allows management of the booth script file.

```shell
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash \
    ./booth install \
    ./booth shell-config
```

Run the wrapper script and follow the instructions.

```shell
./booth
```

### Updating CodingBooth

To update CodingBooth to the latest version:

```shell
# Install/update to the latest version
./booth install

# Install/update to a specific version
./booth install 0.28.0

# Pull the latest images (optional, happens automatically if not present)
./booth --pull
```

The wrapper script downloads the `codingbooth` binary for your platform to the shared cache. If the binary is already up-to-date, the download is skipped.

> **Note:** The version is a positional argument: `./booth install 0.28.0`, not `./booth install --version 0.28.0`.

> **Note:** The `booth` script operates relative to its own location, not the current working directory. This means you can run `/path/to/project/booth` from anywhere and it will correctly find the `.booth/` configuration in the project folder.

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
| `--writable-booth` | Allow writing to `.booth/` inside the container (read-only by default)            |
| `--silence-build`  | Suppress build/startup output                                                    |
| `--dryrun`         | Print docker commands without executing                                          |
| `--verbose`        | Enable debug output                                                              |
| `--config <path>`  | Use custom config file                                                           |
| `--code <path>`    | Set code directory                                                               |
| `--boothfile <path>` | Use specific Boothfile (compiles to Dockerfile)                                |
| `--emit-dockerfile` | Print generated Dockerfile without building                                     |
| `--strict`         | Treat Boothfile warnings as errors                                               |
| `--help`, `-h`     | Show help information                                                            |

### Wrapper vs Binary Commands

The `booth` script is a **wrapper** that manages the underlying `codingbooth` binary. They have separate help and version commands:

| Command            | What it shows                               |
|--------------------|---------------------------------------------|
| `./booth help`     | Wrapper help (install, update, cache, etc.) |
| `./booth --help`   | Binary help (run flags, variants, etc.)     |
| `./booth version`  | Wrapper + binary version info               |
| `./booth --version`| Binary version only                         |

> 💡 **Tip:** Use `booth help` to learn about managing CodingBooth installations. Use `booth --help` to see runtime options for launching containers.

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

### Browsing Templates

Use `booth template` to explore available init templates:

```shell
# List available templates
./booth template list

# Search by name, description, or tag
./booth template search python

# Show detailed info about a template
./booth template show go

# Show extension details
./booth template show python+uv

# Show full file/segment contents
./booth template show go --detail

# Show raw code/content of a template
./booth template cat go
```

> 💡 **Tip:** Use `--full` with `list` or `search` to include secondary (non-primary) templates.

### Project Scaffolding (`booth init`)

Create a complete `.booth/` configuration from templates — no manual Dockerfile writing needed.

```shell
# Create a polyglot project with IDE support
./booth init new --select go+linter/python:3.13+uv/claude-code --variant codeserver

# Preview without writing files
./booth init dryrun --select rust+clippy

# Re-generate after adding a template
./booth init adjust --select go+linter/python+uv/postgresql
```

The selection DSL supports templates (`go`), versions (`python:3.13`), extensions (`+uv`), and exclusions (`~credential`). Selections can come from inline strings, recipe files (`@file`), or URLs (`@@url`).

See **[booth init documentation](docs/BOOTH_INIT.md)** for the full guide.


### Container Lifecycle (`--keep-alive`)

By default, containers are removed on exit. Use `--keep-alive` to preserve the container so you can resume later.

```shell
# Start a persistent booth
./booth --keep-alive --name myproject

# Resume after exiting
./booth start myproject

# Manage containers
./booth list                  # show all booths
./booth stop myproject        # stop a running booth
./booth prune --yes           # clean up all stopped booths
```

See **[booth lifecycle documentation](docs/BOOTH_LIFECYCLE.md)** for the full guide.


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

| Input Alias  | Resolved Variant |
|--------------|------------------|
| default      | base             |
| console      | base             |
| ide          | codeserver       |
| notebook     | notebook         |
| codeserver   | codeserver       |
| desktop      | desktop-xfce     |
| xfce         | desktop-xfce     |
| kde          | desktop-kde      |

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

## Customization

CodingBooth is highly customizable. You can tailor how your environments run by adjusting configuration files or using runtime flags. 

For a complete guide on how to customize CodingBooth environments, see the following documentation:

- **[Booth Customization Guide](docs/BOOTH_CUSTOMIZATION.md)**: Covers how to use setup scripts, install scripts, create templates, and share reusable environment recipes.
- **[Boothfile Reference](docs/plans/Boothfile.md)**: Detailed specification for the simplified, script-like format used to define container environments.

### The `.booth/` Folder (Quick Overview)

All booth configuration lives in a single `.booth/` folder in your project root:

```
my-project/
└── .booth/
    ├── config.toml     # Launcher configuration
    ├── Boothfile       # Simplified build script (optional, preferred)
    ├── Dockerfile      # Custom Docker build (optional, fallback)
    ├── .env-local      # Personal env vars (optional, gitignored)
    ├── setups/         # Custom setup scripts (optional)
    ├── home/           # Team-shared home directory files (optional)
    └── tools/          # Managed by booth wrapper (auto-created)
```

>  **Read-only by default:** The `.booth/` folder is mounted **read-only** inside the container to prevent accidental or malicious modifications to your configuration. Use `--writable-booth` if you need to edit `.booth/` files from inside the container.

---

## Guarantees & Limits

- ✅ **Host file ownership:** All files in your project folder remain owned by your host user — no "root-owned" files.
- ✅ **Consistent user mapping:** Each container automatically creates a matching user and group via `booth-entry`.
- ⚠️ **Cross-OS caveats:** CodingBooth doesn't abstract away all host OS differences — things like line endings, symlinks, or file attributes may still vary between platforms.

### Security Considerations

CodingBooth is designed for development environments, not production workloads. Key security aspects:

| Aspect               | Behavior                                                                  |
|----------------------|---------------------------------------------------------------------------|
| **User privileges**  | Processes run as unprivileged `coder` user, not root                      |
| **Sudo access**      | `coder` has passwordless sudo (for installing packages)                   |
| **File ownership**   | Files match your host UID/GID — no root-owned files                       |
| **`.booth/` config** | Read-only inside the container by default (`--writable-booth` to opt out) |
| **Network**          | Full network access by default                                            |
| **DinD mode**        | Requires `--privileged` flag (elevated permissions)                       |

**Best practices:**
- Don't run untrusted code in CodingBooth containers
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

CodingBooth mirrors your host identity inside the container — you work as yourself, not as root. This results in a seamless development environment with no permission headaches.

To learn more about how CodingBooth achieves this, data persistence rules, and in-container documentation, see the **[How It Works Guide](docs/HOW_IT_WORKS.md)**.

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

    # OpenAI Codex
    "-v", "~/.codex:/etc/cb-home-seed/.codex:ro",

    # Firebase CLI
    "-v", "~/.config/configstore/firebase-tools.json:/etc/cb-home-seed/.config/configstore/firebase-tools.json:ro",

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


## `booth run` Reference

`booth run` (or simply `./booth`) starts a containerized development environment. It handles image selection, port mapping, user permissions, and multiple run modes.

For the full reference, see **[booth run documentation](docs/BOOTH_RUN.md)**.

Key topics covered:

- **Image selection** — Repository, variant, version, and precedence rules
- **Config files** — `.booth/config.toml`, `.env`, `.env-local` and custom argument arrays
- **Run modes** — Interactive shell, command mode (`-- <cmd>`), silent mode, daemon mode
- **Ports** — Automatic mapping, fixed ports, `NEXT`, and `RANDOM`
- **Keep-alive** — Preserve containers for later resumption (see also [Lifecycle](docs/BOOTH_LIFECYCLE.md))
- **Docker-in-Docker** — Build and run containers inside your booth
- **Dry-run** — Preview the `docker run` command without executing
- **TLS** — Self-signed certificates for HTTPS access


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
1. **Startup script**: runs once per container start, as the normal user.
2. **Profile script**: sourced at the beginning of every shell session.
3. **Starter wrapper**: a user-invoked command wrapper.

For a detailed explanation of script naming conventions, profile ordering, idempotence, and environment variable logic, see the **[Booth Setup Guide](docs/BOOTH_SETUP.md)**.


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


## Documentation

User-facing guides:

- **[booth run](docs/BOOTH_RUN.md)** — Running containers: image selection, config files, run modes, ports, DinD, TLS
- **[booth init](docs/BOOTH_INIT.md)** — Template-driven project scaffolding
- **[booth example](docs/BOOTH_EXAMPLE.md)** — Pre-built example workspaces
- **[booth lifecycle](docs/BOOTH_LIFECYCLE.md)** — Container lifecycle: keep-alive, start, stop, restart, remove, prune

For deeper technical details on how CodingBooth works internally, see [docs/implementations/](docs/implementations/):

- **[Booth Init](docs/implementations/BOOTHINIT.md)** — Template-driven project scaffolding (`booth init` and `booth template`)
- **[Booth Lifecycle](docs/implementations/BOOTH_LIFECYCLE.md)** — Container lifecycle management implementation
- **[Examples](docs/implementations/EXAMPLES.md)** — Examples system and release workflow
- **[Wrapper](docs/implementations/WRAPPER.md)** — The booth wrapper script that manages binary downloads and verification
- **[User Permissions](docs/implementations/USER_PERMISSIONS.md)** — UID/GID mapping between host and container
- **[Desktop + noVNC](docs/implementations/DESKTOP_NOVNC.md)** — VNC server and browser-based desktop access
- **[Variant Selection](docs/implementations/VARIANTS.md)** — How variants and aliases are resolved
- **[Docker-in-Docker](docs/implementations/DIND.md)** — Running Docker inside CodingBooth
- **[Booth-in-Booth](docs/implementations/BOOTH_IN_BOOTH.md)** — Nested booth detection and opt-in mechanism


## Developer Setup

If you're contributing to CodingBooth, run the onboarding script to set up git hooks:

```bash
./on-board-me.sh
```

This activates a **pre-commit hook** that prevents committing when `version.txt` and `README.md` have mismatched versions.
The hook only triggers when either file is staged — it won't interfere with unrelated commits.


## Community & Feedback

CodingBooth is built to meet **real developer needs** — simple, reproducible, and flexible without unnecessary complexity.  
Your feedback and contributions help it evolve and stay relevant for everyone.

### 🐛 Issues & Contributions

- **Report Bugs & Request Features:** Use the **[Issues page](../../issues)** to report bugs, request features, or suggest improvements.
- **Pull Requests:** PRs are always welcome — but I reserve the right to reject any PR that doesn't align with my vision for the project.
- **Discussions:** Have a creative idea, workflow, or enhancement to share? Open an issue or discussion — we’d love to hear it.
- **Direct Contact:** Prefer to reach out directly? Feel free to contact me through any of the links below.

### 💖 Support & Appreciation

If CodingBooth has saved you time, simplified your setup, or made development more enjoyable, please consider supporting the project:

- **[Sponsor me on GitHub](https://github.com/sponsors/NawaMan)** ❤️
- **[Buy me a coffee](https://buymeacoffee.com/NawaMan)** ☕

Your encouragement keeps this project active — and might even help with my kids’ college fund 😄.

### 🌐 Connect

Stay in touch or follow updates, insights, and development notes:

- 🐦 **Twitter/X:** [@nawaman](https://x.com/nawaman)
- 💼 **LinkedIn:** [nawaman](https://www.linkedin.com/in/nawaman/)
- 📰 **Blog:** [nawaman.net/blog](https://nawaman.net/blog/)

---

> 🙏 Every issue, idea, and pull request — big or small — helps make CodingBooth better for everyone.  
> Thank you for being part of the community!
