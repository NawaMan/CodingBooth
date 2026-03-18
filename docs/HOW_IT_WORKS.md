# How CodingBooth Works

The `booth` wrapper script is **location-based**: it operates relative to its own location, not the current working directory. This means:
- Running `./booth` from the project root works as expected
- Running `/path/to/project/booth` from any directory also works correctly
- The script always finds `.booth/` in the same directory where `booth` is located

1. The launcher passes your **host UID** and **GID** into the container using the environment variables `HOST_UID` and `HOST_GID`.  
2. Inside the container, the entrypoint script (`booth-entry`) ensures a matching `coder` user and group exist with those IDs.  
3. The directories `/home/coder` and `/home/coder/code` are owned by that user, ensuring smooth file sharing between host and container.  
4. Add the user `coder` to sudoers so that it can sudo without needing the password
5. Prepare `.bashrc` and `.zshrc`
6. Run startup scripts (system scripts from `/usr/share/startup.d/`, then user scripts from `.booth/startups/`)
7. All commands run as the unprivileged **`coder`** user, not `root`, preserving security and consistent file ownership.

```
host                                     # your machine
  ├── ~/.cache/codingbooth/              # shared binary cache
  |    └── versions/
  |         └── <version>/               # version-specific binary
  |              ├── codingbooth.sha256
  |              └── codingbooth-<os>-<arch>  # binary for current platform
  ├── project/                           # your project folder on the host
  |    ├── booth                         # booth wrapper script
  |    ├── .booth                        # booth internal folder
  |    |    └── tools/
  |    |         └── codingbooth.lock    # version reference
  |    ├── ...                           # other project files
  ...

container
  ├── home/
  |    ├── coder/
  |    |    ├── code/                           # your project folder inside the container
  |    |    |   ├── booth                       # booth wrapper script
  |    |    |   ├── .booth                      # booth internal folder
  |    |    |   |    └── tools/
  |    |    |   |         └── codingbooth.lock  # version reference
  |    |    ├── ...                             # other project files
  |    ├── ...                                  # other home files
  ├── etc/
  |    ├── profile.d/                           # profile script folder
  ├── opt/
  |    ├── codingbooth/
  |    |    ├── setups/                         # setup script folder
  |    |    |    ├── ...                        # setup scripts
  ├── usr/
  |    ├── local/
  |    |    ├── bin/                            # program file folder
  |    ├── share/
  |    |    ├── startup.d/                      # startup script folder
  ...
```

---

> 🧠 **In short:**
> CodingBooth mirrors your host identity inside the container — you work as yourself, not as root.


**Result:** seamless dev environment, no permission headaches.

### Data Persistence

Understanding what persists across container restarts is critical:

| Location                          | Persists? | Notes                                               |
|-----------------------------------|-----------|-----------------------------------------------------|
| `/home/coder/code/`               | **Yes**   | Bind-mounted from host; this is your project folder |
| `/home/coder/` (outside `code/`)  | Partial   | Ephemeral by default; use `.booth/cache/` to persist specific files |
| `/opt/`, `/usr/`, `/etc/`         | No        | System directories; lost on restart                 |
| Installed packages                | No        | Must be in Dockerfile to persist                    |

**What this means:**
- **Your code is safe** — it lives on the host and is never lost
- **Home directory customizations** — use `.booth/home/` or `.booth/home-seed/` to persist dotfiles (see [Home Directory Guide](BOOTH_HOME.md))
- **Home directory state** — use `.booth/cache/` to persist shell history, tool configs, and other runtime state across sessions (see [Local Cache Guide](BOOTH_LOCALCACHE.md))
- **Installed tools** — add them to your `.booth/Dockerfile` (or `Boothfile`) so they're rebuilt each time
- **Container state** — treat containers as disposable; rebuild rather than modify

### Home Directory Seeding

At container startup, `booth-entry` populates the home directory from four sources in order:

1. **`.booth/home-seed/`** — Team defaults (no-clobber: won't overwrite existing files)
2. **`.booth/home/`** — Team overrides (will overwrite existing files)
3. **`/etc/cb-home-seed/`** — Host personal defaults (no-clobber)
4. **`/etc/cb-home/`** — Host personal overrides (will overwrite)

Each source supports fine-grained control with the `.mount-this` marker. A directory containing `.mount-this` is copied as a unit; directories without it copy only individual files and recurse into subdirectories. This allows precise control — for example, seeding only `.credentials.json` from `~/.claude/` without overwriting other cached settings.

See the [Home Directory Guide](BOOTH_HOME.md) for details and examples.

> 💡 **Tip:** If you need to persist something outside `/home/coder/code/`, use `.booth/cache/`, add it to your Boothfile/Dockerfile, or mount an additional volume via `run-args` in `config.toml`.

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
    ├── nodejs--setup.sh
    └── ...
```

Run `booth--info` inside the container to see a quick overview of your environment.
