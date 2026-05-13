# Variants

CodingBooth provides several **ready-to-use container variants** designed for different development workflows.
Each variant comes pre-configured with a curated toolset and a consistent runtime environment.

## Available Variants

- **`base`** – A minimal base image with essential shell tools.
  Ideal for building custom environments, running CLI applications, or lightweight automation tasks.
  The terminal is exposed with [ttyd](https://github.com/tsl0922/ttyd) on port 10000.

- **`notebook`** – Includes [Jupyter Notebook](https://jupyter.org/) with Bash and other utilities.
  Great for data science, analytics, documentation, or interactive scripting workflows.

- **`codeserver`** – A web-based VS Code environment powered by [`code-server`](https://github.com/coder/code-server).
  Provides a full browser-accessible IDE with Git integration, terminals, and extensions.

- **[`desktop-xfce`]( https://www.xfce.org  )**, **[`desktop-kde`]( https://kde.org/plasma-desktop)** – Full Linux desktop environments accessible via browser or remote desktop (e.g., [noVNC](https://novnc.com)).
  Useful for GUI-heavy workflows or running native IDEs like [IntelliJ IDEA](https://www.jetbrains.com/idea/), [PyCharm](https://www.jetbrains.com/pycharm/), or [Eclipse](https://www.eclipse.org) inside Docker.

All variants expose their UI on port 10000 but NEXT and RANDOM can be used. See [Port](BOOTH_RUN.md#6-ports) for more details.

## Aliases & Defaults

CodingBooth supports several shortcuts and aliases for variant names:

| Input Alias  | Resolved Variant |
|--------------|------------------|
| default      | base             |
| console      | base             |
| terminal     | base (cmd: bash) |
| ide          | codeserver       |
| notebook     | notebook         |
| codeserver   | codeserver       |
| desktop      | desktop-xfce     |
| xfce         | desktop-xfce     |
| kde          | desktop-kde      |

The `terminal` alias resolves to the `base` variant but automatically sets the command to `bash`, giving you a direct terminal session in your host terminal — equivalent to `booth -- bash`. If you pass explicit commands (e.g., `booth --variant terminal -- zsh`), your commands take precedence.

If an unknown value is provided, CodingBooth will exit with an error listing supported variants and aliases.

## Desktop Configuration

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

### noVNC Resize Modes

When accessing the desktop through your browser, noVNC supports different resize modes:

- **`remote`** (default) – Dynamically resizes the remote desktop to match your browser window size. The `GEOMETRY` setting becomes the initial size.
- **`scale`** – Scales the desktop to fit your browser window while maintaining the resolution set by `GEOMETRY`.
- **`off`** – No resizing or scaling; displays the desktop at native resolution (1:1 pixel mapping).

To use a specific resize mode, append `&resize=off` or `&resize=scale` to the noVNC URL:
```
http://localhost:<PORT>/vnc.html?autoconnect=1&host=localhost&port=<PORT>&path=websockify&resize=off
```

> **Tip:** `<PORT>` is the host port your booth is mapped to (default 10000, or as configured via `--port` or `config.toml`). The desktop startup message shows the correct URL with the actual port.

> **Tip:** If you set a specific resolution like `1920x1080`, you may want to use `resize=off` to see it at native resolution, or `resize=scale` to fit it within your browser window.

### Clipboard Limitations

noVNC does not have direct clipboard integration with your host machine. To copy and paste text between the remote desktop and your host:

1. Click the arrow on the left edge of the screen to open the noVNC side panel
2. Select the clipboard icon
3. Use the text area to transfer clipboard content:
   - **To paste into VNC:** Paste text into the panel, then Ctrl+V inside the desktop
   - **To copy from VNC:** Copy text inside the desktop, then copy from the panel to your host

## Code Server Notes

### Clipboard in Terminal

When pasting into the integrated terminal, your browser may show a "Paste" confirmation popup instead of pasting directly. This is a browser security feature for clipboard access. Simply click the popup or press Enter to confirm the paste.

This behavior is inconsistent because it depends on several browser conditions:
- **Clipboard permission granted** — Once allowed, pastes may work directly for that session
- **Terminal has focus** — Clicking directly into the terminal before pasting helps
- **Recent user gesture** — Browsers require recent interaction (click/keypress); paste immediately after clicking and it works, wait too long and the popup appears
- **HTTPS context** — Clipboard API is more reliable over HTTPS; HTTP localhost can be inconsistent

When all conditions align, paste works directly. When any condition isn't met, the confirmation popup appears.

## Typical Use Cases

- **Data Science & Notebooks** – Quickly spin up reproducible Jupyter environments using `--variant notebook`.
  Ideal for experiments, reports, or teaching interactive examples.

- **Executable Bash Notebooks** – Use `--variant notebook` to work in a Jupyter environment that includes a **Bash kernel**.
  This allows you to write notebooks that mix explanations, commands, and output in one place — effectively turning a notebook into a runnable document.
  It's ideal for creating repeatable build instructions, walkthroughs, tutorials, or Makefile-like automation that is much more readable and approachable than shell scripts alone.

- **Web or App Development** – Develop directly in a browser-based IDE using `--variant codeserver`, complete with terminal and Git integration.

- **Lightweight CLI Workflows** – Use `--variant base` for scripting, building, and testing in an isolated but fast shell environment.

- **Direct Terminal Sessions** – Use `--variant terminal` to drop straight into a bash session inside the container, without opening a browser. This is useful for quick tasks, scripting, or when you prefer working in your host terminal rather than a web-based UI.

- **GUI Development Environments** – Run full desktop IDEs or graphical tools using `--variant desktop-*`.
  Perfect for complex projects requiring a windowed environment without polluting your host.

- **Continuous Integration & Training** – Standardize development or CI environments for teams and classrooms, ensuring consistent behavior across machines.

---

> **Tip:** You can override the variant at runtime using:
> ```bash
> ./booth --variant codeserver
> ```
> Or set it permanently in your configuration file (`.booth/config.toml`).
