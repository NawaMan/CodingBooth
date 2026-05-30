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
