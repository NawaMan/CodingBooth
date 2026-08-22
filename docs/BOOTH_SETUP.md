# Setup Implementation Notes

Conventions for the setup scripts in `variants/base/setups/` — the trio of artifacts they produce,
the ordering levels, and the shared helpers they reuse.

> **Working on the catalog?** This file is the *reference*. The **`setup-work` skill** is the
> workflow that uses it — adding, modifying, or fixing a setup, template, or extension, including
> how to try a change without rebuilding an image.
>
> | Also see | For |
> | --- | --- |
> | `templates/README.md` | Boothfile segment order bands, arg style, run-args, autostart + expose |
> | `docs/AGENT_TEMPLATE.md` | the `template.toml` / `*--extension.toml` schema |
> | `docs/BOOTH_CUSTOMIZATION.md` | the *user* side — custom setups in a project's `.booth/setups/` |

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
`/etc/profile.d/<LEVEL>-cb-<thing>--profile.sh` and `/usr/share/startup.d/<LEVEL>-cb-<thing>--startup.sh`

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
  - Startup: `/usr/share/startup.d/<LEVEL>-cb-<thing>--startup.sh`  
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
  ```

**Environment variables**
- Prefer the `CB_*` prefix for CodingBooth-specific variables (e.g., `CB_PYTHON_HOME`).
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
- Startup: `chmod 755`
- Profile: `chmod 644`
- Starter: `chmod 755`

**Sourcing a profile that may not be there**

Guard an optional `source` with `-f`. Do **not** rely on `2>/dev/null || true` alone:

```bash
# Right
[ -f /etc/profile.d/53-cb-python--profile.sh ] \
    && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# Wrong — exits the script under bash 3.2, before `|| true` is consulted
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
```

Bash 3.2 — what macOS ships — treats a `source` that cannot find its file as fatal and exits the
shell; bash 5, which every booth runs, carries on and lets `|| true` do its job. The two agree in
production and disagree the moment a test runs the script on a Mac host, where the profile does not
exist. The same applies to a glob (`source /etc/profile.d/*-cb-go--profile.sh`): an unmatched glob
stays literal and is just as fatal, so loop over the matches and `-f` each one.

A profile the script genuinely *requires* is a different case — source it unguarded and let the
failure be loud (`java-nb-kernel--setup.sh` does this with the JDK profile).

---

## Shared helpers

`variants/base/setups/` ships helpers that setup scripts are expected to reuse rather than
reimplement. The whole directory is copied to `/opt/codingbooth/setups/` (which is on `PATH`), so a
script reaches a sibling through its own directory:

```bash
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
```

### Bailing out when a prerequisite is missing — `libs/skip-setup.sh`

A setup that is only meaningful alongside another tool (a VS Code extension, a notebook kernel, a
desktop app) must exit **gracefully** when its host is absent, or it takes down every build of a
variant that does not have that host.

```bash
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi
```

`skip_setup` prints `SKIP: <script> - <reason>` and exits **0** under a Dockerfile build (no TTY) so
the build continues, or **42** interactively to signal "not applicable" to the caller. Never
`exit 1` for a condition that just means "not for this variant".

### Detecting what the image has

| Helper | Returns 0 when |
| --- | --- |
| `cb-has-vscode.sh` | VS Code or code-server is installed |
| `cb-has-jetbrains.sh` | a JetBrains IDE is installed (any `/opt/*/product-info.json`) |
| `cb-has-desktop.sh` | a desktop environment is **installed** (X11/VNC, XFCE, KDE, Wayland) |
| `cb-has-desktop-running.sh` | a desktop is **currently running** (checks processes, not packages) |

Use `cb-has-desktop.sh` at build time and `cb-has-desktop-running.sh` from startup scripts.

### VS Code extensions — `libs/code-extension-source.sh`

```bash
source "$SCRIPT_DIR/libs/code-extension-source.sh"
install_extensions golang.go
```

It installs into both `code` and `code-server` (which do **not** share an extension registry or
marketplace), and defers the install to first launch under QEMU, where code-server's bundled Node
fails with `Invalid ELF image` on a cross-architecture build.

### JetBrains IDEs — `libs/jetbrains-source.sh`

```bash
source "$SCRIPT_DIR/libs/jetbrains-source.sh"
jb_ides                                  # "<ide><TAB><install-dir>" per IDE found
jb_ensure_plugins_path "$INSTALL_DIR"    # point the IDE at /opt/jetbrains-plugins/<product>
jb_build_id "$INSTALL_DIR"               # IC-252.26830.84, what the marketplace asks for
jb_resolve_id 6317                       # numeric marketplace id -> xmlId
```

Everything is read from the `product-info.json` each IDE ships. Plugins go to an image-level dir
rather than `~/.local/share/JetBrains/`, because the container home is recreated per run — a
plugin installed into `$HOME` at build time is gone before anyone opens the IDE.

### Desktop icons — `cb-desktop-icon.sh` and `cb-web-icon.sh`

`/etc/skel/Desktop` is the single registry of "apps to surface on the desktop": `booth-entry` seeds
it into each user's `~/Desktop` on XFCE/KDE/LXQt, and the Wayland variant turns each entry into a
waybar panel button. Do not write into it directly — go through a helper, and both behaviours come
for free. Both no-op off-desktop.

**A GUI app** that already ships a `.desktop` launcher. Each argument may be a path to a `.desktop`
file, a basename in `/usr/share/applications`, or a bare app token it resolves for you. Unresolvable
apps are logged and skipped, never fatal — so it is safe to call unconditionally:

```bash
cb-desktop-icon.sh chromium.desktop      # basename
cb-desktop-icon.sh bluej                 # app token
```

**A web service** (an HTTP server on an internal port). This also writes
`/etc/cb-web-services/<id>.conf`, the descriptor `cb-web-open` reads to resolve the URL at click
time:

```bash
cb-web-icon.sh --id excalidraw --name "Excalidraw" --icon "$ICON" \
               --port-env EXCALIDRAW_PORT --port 16000
```

`tests/config/test90-web-servers-have-desktop-icon.sh` guards that every template starting a web
server registers an icon this way.

---

## Custom Setups
You can create your own setup scripts to install any tool you need.
Simply copy into your docker image and run it just like other setup scripts.
