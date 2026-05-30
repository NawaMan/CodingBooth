# Booth-in-Booth (Nested Booth) Implementation

> [!IMPORTANT]
> **Why this matters:** When your project folder is mounted inside a CodingBooth container, the `booth` script is visible at `/home/coder/code/booth`. Users might accidentally run it, creating unintended nested containers. This protection prevents that while still allowing intentional nested execution.

**Preventing accidental nested booth execution.**
The booth wrapper includes detection logic that identifies when it's running inside a CodingBooth container and blocks execution by default. This protects users from accidentally starting a booth-inside-a-booth, which can cause port conflicts, resource waste, and confusion. For legitimate use cases (like testing CodingBooth itself or running isolated environments), users can explicitly opt-in with environment variables and flags.

---

## The Problem

When you start a CodingBooth container, your project folder is bind-mounted to `/home/coder/code`. This means the `booth` wrapper script is visible inside the container:

```
/home/coder/code/
├── booth              <- The wrapper script is here!
├── .booth/
│   ├── config.toml
│   └── Dockerfile
└── src/
    └── ...
```

A user inside the container might:
- Accidentally type `./booth` thinking they're on the host
- Tab-complete to `booth` and run it unintentionally
- Copy-paste commands from documentation without realizing they're inside a container

This leads to:
- **Port conflicts** — The nested booth tries to use the same port as the parent
- **Resource waste** — Unnecessary containers consuming memory and CPU
- **Confusion** — Multiple nested environments are hard to reason about
- **Docker socket issues** — Without DinD, the nested booth can't access Docker

---

## The Solution: Detection and Opt-In

The wrapper script detects container context and requires explicit opt-in for nested execution:

```
Outside container          Inside container
      │                          │
      ▼                          ▼
   ./booth              ./booth (blocked by default)
      │                          │
      │                          ▼
      │               BOOTH_IN_BOOTH=true?
      │                    │         │
      │                   No        Yes
      │                    │         │
      │                    ▼         ▼
      │               Error with   Port different?
      │               instructions      │
      │                            No   │   Yes
      │                            │    │    │
      │                            ▼    │    ▼
      │                         Error   │  Continue
      │                                 │    │
      ▼                                 ▼    ▼
   Normal execution              Normal execution
```

---

## Detection Mechanism

The wrapper detects it's inside a CodingBooth container by checking for either:

1. **Directory marker**: `/opt/codingbooth/` exists
2. **Environment variable**: `CB_CONTAINER_NAME` is set

Both are present in all CodingBooth containers. The directory is part of the base image, and the environment variable is set by the launcher.

```bash
# Detection logic (simplified)
if [[ -d "/opt/codingbooth" || -n "${CB_CONTAINER_NAME:-}" ]]; then
    # We're inside a CodingBooth container
fi
```

---

## Requirements for Nested Execution

To run a booth inside a booth, you must satisfy **all** of these requirements:

### 1. Set `BOOTH_IN_BOOTH=true`

This environment variable explicitly acknowledges you want nested execution:

```bash
export BOOTH_IN_BOOTH=true
```

### 2. Specify a Different Port

The nested booth must use a different port than the parent container. The wrapper checks against:

- `CB_HOST_PORT` — The parent container's host-facing port
- `CB_CODE_PORT` — The parent container's internal port (always 10000)

Valid port specifications:

```bash
# Auto-find next available port (recommended)
./booth --port NEXT ...

# Use a random available port
./booth --port RANDOM ...

# Explicit different port
./booth --port 11000 ...
```

### 3. Enable Docker-in-Docker (`--dind`)

**This is critical.** Without `--dind`, the nested booth cannot access Docker because:

- The parent container doesn't have the Docker socket mounted (by design)
- The nested booth needs a Docker daemon to build and run containers

```bash
./booth --dind --port NEXT ...
```

> [!WARNING]
> Without `--dind`, the nested booth will fail when trying to run Docker commands. The wrapper doesn't enforce this automatically because some use cases (like running non-Docker commands) don't require it.

---

## Complete Example

Running a nested booth for testing:

```bash
# Inside a CodingBooth container

# Set the opt-in flag
export BOOTH_IN_BOOTH=true

# Run nested booth with DinD and auto-selected port
./booth --dind --port NEXT --variant codeserver

# Or run a specific command
./booth --dind --port NEXT -- make test
```

---

## Error Messages

### When `BOOTH_IN_BOOTH` is not set:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    Running booth inside a booth container                 ║
╠═══════════════════════════════════════════════════════════════════════════╣
║ You appear to be running 'booth' from inside a CodingBooth container.    ║
║ This is usually accidental - the booth script is visible here because    ║
║ your project folder is mounted at /home/coder/code.                       ║
║                                                                           ║
║ If you intentionally want to run a nested booth (booth-in-booth), set:   ║
║                                                                           ║
║     export BOOTH_IN_BOOTH=true                                            ║
║                                                                           ║
║ AND specify a different port (not the current container's port):         ║
║                                                                           ║
║     ./booth --port NEXT ...                                               ║
║     ./booth --port 11000 ...                                              ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### When port is not specified:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         Port conflict in nested booth                     ║
╠═══════════════════════════════════════════════════════════════════════════╣
║ BOOTH_IN_BOOTH=true is set, but no port was specified.                    ║
║                                                                           ║
║ You must specify a different port to avoid conflicts with this container: ║
║   Current container's host port: 10000                                    ║
║   Current container's code port: 10000                                    ║
║                                                                           ║
║ Use one of:                                                               ║
║     ./booth --port NEXT ...      (auto-find next available port)          ║
║     ./booth --port RANDOM ...    (use a random port)                      ║
║     ./booth --port 11000 ...     (explicit different port)                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### When port conflicts:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         Port conflict in nested booth                     ║
╠═══════════════════════════════════════════════════════════════════════════╣
║ The requested port (10000) conflicts with this container's host port.    ║
║                                                                           ║
║ Use a different port:                                                     ║
║     ./booth --port NEXT ...      (auto-find next available port)          ║
║     ./booth --port RANDOM ...    (use a random port)                      ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Architecture: Nested Booth with DinD

When running a nested booth with `--dind`, the architecture looks like this:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                   Host                                       │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                    Parent Booth Container                              │  │
│  │                    (port 10000)                                        │  │
│  │                                                                        │  │
│  │  /home/coder/code/                                                     │  │
│  │  ├── booth  ← User runs: BOOTH_IN_BOOTH=true ./booth --dind --port NEXT│  │
│  │  └── ...                                                               │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │  │
│  │  │              Nested DinD Sidecar                                 │  │  │
│  │  │              (docker:dind)                                       │  │  │
│  │  │              Port 11000 → Host                                   │  │  │
│  │  │                    ▲                                             │  │  │
│  │  │                    │ shared network                              │  │  │
│  │  │                    ▼                                             │  │  │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │           Nested Booth Container                           │  │  │  │
│  │  │  │           DOCKER_HOST=tcp://localhost:2375                 │  │  │  │
│  │  │  └────────────────────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  Exposed ports: 10000 (parent), 11000 (nested)                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Bypassed Commands

The following wrapper commands bypass the nested booth check entirely:

| Command        | Reason                                      |
|----------------|---------------------------------------------|
| `help`         | Read-only, informational                    |
| `version`      | Read-only, informational                    |

These are handled early in the wrapper before the detection runs.

---

## Environment Variables Reference

| Variable            | Set By        | Purpose                                      |
|---------------------|---------------|----------------------------------------------|
| `CB_CONTAINER_NAME` | Launcher      | Container name, used for detection           |
| `CB_HOST_PORT`      | Launcher      | Parent's host-facing port                    |
| `CB_CODE_PORT`      | Launcher      | Parent's internal port (always 10000)        |
| `BOOTH_IN_BOOTH`    | User          | Opt-in flag for nested execution             |

---

## Use Cases

### Testing CodingBooth Development

When developing CodingBooth itself, you may want to test changes inside a container:

```bash
# Inside development container
export BOOTH_IN_BOOTH=true
./booth --dind --port NEXT --variant base -- echo "Nested booth works!"
```

### Isolated CI/CD Simulation

Running a nested environment to simulate CI behavior:

```bash
export BOOTH_IN_BOOTH=true
./booth --dind --port NEXT -- make ci-test
```

### Multi-Environment Development

Running different booth variants simultaneously:

```bash
# Terminal 1: Parent booth with codeserver
./booth --variant codeserver --port 10000

# Terminal 2 (inside parent): Nested booth with notebook
export BOOTH_IN_BOOTH=true
./booth --dind --port 11000 --variant notebook
```

---

## Limitations

1. **Performance overhead** — Nested containers add latency and memory usage
2. **Port management** — You must track which ports are in use
3. **Complexity** — Debugging issues across nested layers is harder
4. **DinD requirement** — Most useful operations require `--dind`

---

## Related Documentation

- [Docker-in-Docker (DinD)](DIND.md) — How DinD works in CodingBooth
- [Wrapper Implementation](WRAPPER.md) — How the booth wrapper script works
- [Variants](VARIANTS.md) — Available container variants
