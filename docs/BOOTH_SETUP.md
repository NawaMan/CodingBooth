# Setup Implementation Notes

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

## Custom Setups
You can create your own setup scripts to install any tool you need.
Simply copy into your docker image and run it just like other setup scripts.

---

## Host-side Shell Setup (the `booth` shell function)

Everything above describes setup *inside* the container image. The host machine
also gets a tiny piece of setup: the `booth` shell function that lets you run
`booth` from any subdirectory of a project.

### What gets installed

`booth shell-config` writes one line to each of `~/.bashrc`, `~/.zshrc`,
`~/.bash_profile`, `~/.profile` (whichever exist):

```bash
unalias booth 2>/dev/null; booth() { local d=$PWD; while [[ $d ]]; do [[ -x $d/booth ]] && { "$d/booth" "$@"; return; }; d=${d%/*}; done; echo "No booth wrapper found. Install: curl -fsSL https://codingbooth.io/install.sh | bash" >&2; return 127; } # booth function v5
```

The function walks up from `$PWD` looking for an executable `./booth` wrapper
and execs it. When no wrapper is found in any ancestor directory, it prints a
one-line install hint and returns 127.

The trailing `# booth function v5` is the version marker. `shell-config` keys
idempotency off it: if the exact suffix is present and nothing else in the file
looks like a CodingBooth booth-function block, the file is skipped. Otherwise
the file is cleaned up (legacy/duplicate blocks removed) and the current v5
line is appended. Re-running `shell-config` always converges to exactly one
booth function per rc file.

### Installing

```bash
./booth shell-config            # idempotent — safe to run any number of times
./booth shell-config --force    # overwrite even if a custom booth() is present
eval "$(./booth shell-config --eval)"   # activate in the current shell only
```

`shell-config` writes a backup of every modified file at `<rc-file>.booth-bak`
before mutating it.

### Uninstalling

Two equivalent entry points:

```bash
./booth shell-config --uninstall   # remove the shell function from all rc files
./booth uninstall --shell-config   # same, but scoped via the uninstall command
```

`booth uninstall --wrapper` and `booth uninstall --all` also remove the shell
function, since an orphan function (pointing at a deleted wrapper) would be
misleading.

### What `shell-config` cleans up

The cleanup pass is intentionally broad so users with legacy installs converge
on the current shape. It removes:

- Fenced blocks: `# >>> CodingBooth shell function ...` through
  `# <<< CodingBooth shell function ...` (every version marker)
- Legacy signature blocks: `# CodingBooth - run '<name>' from any subdirectory`
  followed by an optional `unalias` line and a `booth()` / `codingbooth()`
  function (one-liner or multi-line, tracked via brace balance)
- Any line ending with `# booth function v<N>` (v5 and any future bumps)

Anything between or around those blocks is preserved unchanged.
