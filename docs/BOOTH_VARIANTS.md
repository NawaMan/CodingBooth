# Variants

CodingBooth provides several **ready-to-use container variants** designed for different development workflows.
Each variant comes pre-configured with a curated toolset and a consistent runtime environment.

## Available Variants

- **`base`** – A minimal base image with essential shell tools.
  Ideal for building custom environments, running CLI applications, or lightweight automation tasks.
  The terminal is exposed with [ttyd](https://github.com/tsl0922/ttyd) on port 10000.
  The split console's document icon starts [viewmd](https://github.com/NawaMan/MarkDownViewer) (`--daemon`, if it is not already serving) and opens it in the pane's web view at `http://booth:8765`. You can also start it from a shell (`viewmd --md README.md`).

- **`notebook`** – Includes [Jupyter Notebook](https://jupyter.org/) with Bash and other utilities.
  Great for data science, analytics, documentation, or interactive scripting workflows.

- **`codeserver`** – A web-based VS Code environment powered by [`code-server`](https://github.com/coder/code-server).
  Provides a full browser-accessible IDE with Git integration, terminals, and extensions.

- **[`desktop-xfce`]( https://www.xfce.org  )**, **[`desktop-kde`]( https://kde.org/plasma-desktop)**, **[`desktop-lxqt`]( https://lxqt-project.org )** – Full Linux desktop environments accessible via browser or remote desktop (e.g., [noVNC](https://novnc.com)).
  Useful for GUI-heavy workflows or running native IDEs like [IntelliJ IDEA](https://www.jetbrains.com/idea/), [PyCharm](https://www.jetbrains.com/pycharm/), or [Eclipse](https://www.eclipse.org) inside Docker.
  `desktop-lxqt` is the lightest of the three — a good choice when you want a desktop with the smallest footprint.

- **[`desktop-wayland`](https://labwc.github.io/)** *(experimental)* – A **Wayland-native** desktop ([labwc](https://labwc.github.io/), a [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) compositor) served to the browser via [wayvnc](https://github.com/any1/wayvnc) + [noVNC](https://novnc.com). The forward-looking counterpart to the X11 desktops above; runs existing X11 apps via Xwayland. **Experimental** — newer and less battle-tested than the X11 desktop variants; if you want a proven desktop today, prefer `desktop-xfce`/`desktop-kde`/`desktop-lxqt`.

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
| lxqt         | desktop-lxqt     |
| wayland      | desktop-wayland  |

The `terminal` alias resolves to the `base` variant but automatically sets the command to `bash`, giving you a direct terminal session in your host terminal — equivalent to `booth -- bash`. If you pass explicit commands (e.g., `booth --variant terminal -- zsh`), your commands take precedence.

If an unknown value is provided, CodingBooth will exit with an error listing supported variants and aliases.

## Desktop Configuration

For desktop variants (`desktop-xfce`, `desktop-kde`, `desktop-lxqt`, `desktop-wayland`), you can customize the screen resolution by setting the `GEOMETRY` environment variable.

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

### Web Preview

The `codeserver` variant includes **CodingBooth: Web Preview**. Start your
application inside the booth, click **Web Preview** (the globe in the status
bar), and enter its port, such as `3000`, or `http://booth:3000/path`. The Command
Palette also provides **CodingBooth: Open Web Preview**. No additional host port
mapping is needed.

The address box also follows the console web panel's web/search rules:

| Input | Opens |
| --- | --- |
| `3000` or `http://booth:3000/path` | A server inside the booth, through its proxy |
| `https://example.com` or `http://example.com` | The external URL directly |
| `example.com/path` | `https://example.com/path` |
| `localhost:3000` | `http://localhost:3000` on the machine running your browser |
| `python async examples` | A Google search, keeping your search text in the address box |

External pages and searches can use separate tabs, duplication, reload, and
**Open in browser** just like booth previews. They load directly, without Booth
URL rewriting. Browsers prevent the controls from reading navigation within
external pages: their saved address remains the one entered in the controls,
and Back/Forward only track destinations opened through those controls.
Some sites block embedding; Google search uses the same `igu=1` URL parameter
as the console panel, but availability still depends on Google and your browser.
Use **Open in browser** if a page refuses to load. An HTTPS booth cannot embed an
HTTP page; use the site's HTTPS address or open it in the browser instead.

Each invocation opens an independent editor tab. Use the **＋** button to duplicate
the current preview, or the status-bar command to open another server. Drag tabs
into editor groups to arrange previews beside code or alongside each other. Each
preview has its own address, back/forward navigation, reload and open-in-browser
controls. Preview tabs and their last addresses restore when the editor reloads;
application memory and navigation history start fresh after a reload.
Use **Developer: Reload Window** in the Command Palette to reload with workspace
state saved. An immediate browser refresh can lose recent tab changes that
code-server has not yet persisted.

`booth` in these addresses means the container. The preview uses the booth's
actual browser address and authenticated `/proxy/<port>/` endpoint to reach the
server. Ports 10000–10007, 18888 and 19999 are reserved for Booth itself.

The code-server proxy shares the console web panel's HTML/CSS/JavaScript URL
rewriting rules, supports WebSockets, and rewrites redirects to stay within the
preview. Booth-server authentication still passes through code-server, which removes its own
session cookie before forwarding requests to application servers. The same
rewriting also applies when opening the full proxy URL in Simple Browser.

Rewriting is best-effort: computed absolute URLs, framework base paths, and
hard-coded WebSocket URLs may need application configuration. Each tab routes
through its own `/proxy/<port>/` path; there is no shared last-selected-port
cookie. Root requests that escape this path are not guessed or routed to a
different tab's server. Use `booth expose` when an application needs its own
origin. Proxied booth apps share the booth's origin, as in the console web panel;
the proxy removes frame-blocking response headers to allow embedding.

The bundled extension is intended for the `codeserver` variant and its Booth
wrapper. Installing standalone code-server using the `codeserver` template does
not add the wrapper or preview extension.

### Clipboard in Terminal

When pasting into the integrated terminal, your browser may show a "Paste" confirmation popup instead of pasting directly. This is a browser security feature for clipboard access. Simply click the popup or press Enter to confirm the paste.

This behavior is inconsistent because it depends on several browser conditions:
- **Clipboard permission granted** — Once allowed, pastes may work directly for that session
- **Terminal has focus** — Clicking directly into the terminal before pasting helps
- **Recent user gesture** — Browsers require recent interaction (click/keypress); paste immediately after clicking and it works, wait too long and the popup appears
- **HTTPS context** — Clipboard API is more reliable over HTTPS; HTTP localhost can be inconsistent

When all conditions align, paste works directly. When any condition isn't met, the confirmation popup appears.

## Notebook Notes

### Web Preview

The `notebook` variant has the same Web Preview controls as code-server. Start your
application inside the booth, open **Web Preview** from the JupyterLab Launcher
(under *Other*), and add its port to the `http://booth:` already in the address
box, such as `http://booth:3000`, or enter any address the
[code-server table above](#web-preview) accepts. The preview opens as a JupyterLab
tab you can dock beside notebooks and terminals. No additional host port mapping
is needed.

Use **＋** (left of the address box) in a preview to open another tab at the same
address, then change its address to show a different server. Each tab is named after the page it shows
(`Web · 8080`, `Web · 8081/docs`) and has its own address and back/forward
history. Drag tabs to arrange them beside notebooks or each other. After a
JupyterLab reload, each tab reopens at the last address it showed.

To read the project's Markdown files, open **Markdown Viewer** from the Launcher,
or click 📄 in any preview to switch it there. Both open `http://booth:8765/`,
the booth's [viewmd](https://github.com/NawaMan/MarkDownViewer), and start it if it
is not running, just like the Console UI's document icon.

Differences from code-server:

- The Launcher tile always brings back its own first tab. Use **＋** for more.
- **Open in browser** opens the page in a new browser tab. A booth server opens
  at its `/proxy/<port>/` address, which needs the same JupyterLab login.
- A tab's latest address is kept in the browser. In a different browser, a
  restored tab reopens at the address it was opened with.
- JupyterLab is set to expose its app object to its own pages
  (`LabApp.expose_app_in_browser`), which is how **＋** opens tabs and names
  them. Previewed apps share JupyterLab's origin, so this gives them nothing
  they could not already reach.

`/proxy/<port>/` is served by the booth's own proxy: each request is first checked
against the JupyterLab login, and JupyterLab's session and `_xsrf` cookies are
removed before it reaches your application, whose own cookies pass through. URL
rewriting, WebSockets and redirect handling are the same as in code-server, with
the same best-effort limits. The Launcher tile comes from
[jupyter-server-proxy](https://github.com/jupyterhub/jupyter-server-proxy), which
`booth-web-preview-notebook--setup.sh` installs in the notebook's Python venv.
Its Launcher plugin supports JupyterLab 4 only, so the notebook installs JupyterLab
4.x (`jupyterlab>=4,<5`) until a compatible version is pinned.

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
