# Security

CodingBooth gives you a **disposable, host-isolated development environment**. This guide explains
exactly what that isolation does and does **not** protect against, so you can decide — per booth —
whether it's safe for what you're about to run inside it.

The single most important idea: **the container boundary is solid; the risk lives in what you put
inside the booth and how much you trust the code that runs there.** This matters most when an AI
agent, a cloned repository, a third-party dependency, or any code you haven't read will execute in
the booth.

> **TL;DR**
> 1. Host-filesystem isolation is **strong** — code inside cannot read the host's `/`, `/tmp`, or
>    other users' files beyond the paths you explicitly mount.
> 2. The weak points are **configuration choices**, not the container engine:
>    - **Convenience mounts** (e.g. `+credential`, `+settings-cache`) bind your real secrets into
>      the booth. Anything inside can read them.
>    - **`--dind` (Docker-in-Docker)** launches a **privileged** sidecar and is, by design, a
>      **host-escape path**. Never enable it for untrusted code.
>    - **The code folder** is read-write. Code in the booth can leave files there that run **on the
>      host** the next time you use git or a build tool in that folder (§1).
>    - **The network is open, including to other booths.** A booth can reach another booth's web
>      UI (a shell, with no password by default), host services on `0.0.0.0`, and your LAN (§1).
> 3. Decide per booth: **trusted code** can keep the conveniences; **untrusted code** must not.
> 4. Before starting a booth that can reach the host as root, booth **stops and asks** (§4).
> 5. CodingBooth prioritizes developer experience over strict isolation. For untrusted or
>    multi-tenant workloads, add the defense-in-depth layers below or use a VM-isolated runtime.

---

## 1. Threat model: what the booth protects

**A booth is a Docker container.** Its job is to isolate the *host* from code running *inside*. It
is **not** a sandbox that protects you from your own secrets being misused once they are inside the
container, and it is **not** a security boundary when you deliberately hand it privileged access
(see §4, DinD).

| Question | Answer |
|----------|--------|
| Can code in the booth read the host filesystem? | **No** — except the paths you explicitly mount. Bind mounts are subtree-pinned; you cannot traverse `..` out of a mount. |
| Can code in the booth escape to root on the host? | **Not** via filesystem, devices, or namespaces in a normal booth (verified). **Yes**, by design, in a `--dind` booth — see §4. |
| Can code in the booth read secrets you mounted in? | **Yes — trivially.** A mounted credential is one `cat` away. `:ro` stops writes, not reads. |
| Are container processes root on the host? | No. They run as the unprivileged `coder` user mapped to your host UID/GID. (`coder` has passwordless `sudo` *inside* the container only — see §5.) |
| Can code in the booth make something run on the host? | **Yes, if you let it.** It can write files in the code folder (git hooks, `.git/config`, build files) that run as you when you next use the folder on the host. With `sudo`, it can also leave a root-owned setuid file there. See [below](#code-folder). |
| Can code in the booth reach other booths? | **Yes.** Docker booths share one network, and their web UIs have no password unless `--public` is used. See [below](#network-reach). |
| Can code in the booth reach the host's network services? | **Only those not bound to `127.0.0.1`.** Services on `0.0.0.0`, your LAN, and the internet are reachable. See [below](#network-reach). |

**Mental model:** treat everything you mount into a booth, and every privilege you grant it, as
"handed to whatever runs inside." The question is never "is the booth isolated?" — it is **"what
did I put inside it, and do I trust the code that will run there?"**

A normal booth is safe enough for code, prompts and skills **you trust**. It is not a sandbox for
code you do not, because of the three things below. Each was checked on a real host (2026-11-23,
CodingBooth 0.83.0, Docker 29.5.2, rootless Podman 5.7.0, Kata with guest kernel 6.18).

<a id="code-folder"></a>
### The code folder works in both directions

The code folder is mounted read-write. Only `.booth/` and the `booth` wrapper are read-only. So code
in the booth can:

- **read everything in it**, including `.env` files and the logins kept under `.booth/cache/`;
- **delete or rewrite work**: uncommitted changes, branches, the reflog, the `.git` directory itself.
  Pushing needs git credentials, which a default booth does not have;
- **leave files that run on the host** the next time you use the folder there:
  - git hooks (`.git/hooks/*`);
  - `.git/config` entries such as `core.fsmonitor`, `core.hooksPath` or an alias. A plain
    `git status` on the host runs `core.fsmonitor`;
  - build and editor files: `Justfile`, `Makefile`, `package.json` scripts, `.vscode/tasks.json`,
    `.envrc`.

  Hooks and `.git/config` are not tracked, so `git status`, `git reset --hard` and `git clean` do not
  show or remove them;
- **with `sudo`, leave a root-owned setuid file.** In the booth, `sudo chown 0:0 f && sudo chmod 4755
  f` shows on the host as `root:root -rwsr-xr-x`. On a filesystem mounted without `nosuid`, which
  includes most `/home` partitions, that file runs **as root** for whoever executes it on the host.
  Kata does not prevent this, because virtio-fs keeps the guest's root ownership. `--sudo false`
  does prevent it (§5).

None of these needs an exploit. Each one waits for you to run something on the host. After untrusted
code has run in a booth:

1. Do not run git, build tools or the editor in that folder on the host.
2. Make a **fresh clone** in a new folder.
3. Copy over only the changes you have reviewed.

Cleaning the old folder in place is not enough.

<a id="network-reach"></a>
### What a booth can reach on the network

Measured from inside a booth:

| Target | Docker | Podman, rootless | `--booth-isolation kata` | Kata + `--egress` |
| --- | --- | --- | --- | --- |
| Host service on `127.0.0.1` | blocked | blocked | blocked | blocked |
| Host service on `0.0.0.0`, via `host.docker.internal` | reached | reached | reached | blocked |
| Host service on `0.0.0.0`, via the host's LAN IP | reached | blocked | reached | blocked |
| **Another booth, by its container IP** (its UI on port 10000) | **reached** | reaches Docker booths; has no container IP of its own | **reached**, in both directions | blocked, in both directions |
| Your LAN (for example the router's admin page) | reached | reached | reached | blocked |
| Internet | open | open | open | allowlist only |

**Why other booths matter.** Docker booths get no `--network` of their own, so they all join
Docker's default bridge, where containers can talk to each other directly. Publishing the UI on
`127.0.0.1` limits only the host side; another container connects to `<container-ip>:10000`. The
Console UI is a writable terminal (`ttyd --writable`). Like code-server and Jupyter, it has no
password unless one is set, and a local booth sets one only with `--public`, which also opens the
port to your network. So **any booth, or any container on the default bridge, can open a shell in
another booth.** A rootless Podman booth reaches Docker booths too, because its traffic leaves
through the host.

Until booths get networks of their own, keep untrusted code in a booth with `--egress`, or in no
booth at all while booths with work you care about are running.

**Why host services matter.** `host.docker.internal` points at the host on purpose, so a booth can
use a database or dev server you run there. Anything bound to `0.0.0.0` is reachable that way, which
includes every `docker run -p <port>:<port>` without an address. Bind host services to `127.0.0.1`
when they need not be reached from a booth.

### Root in the booth is root on the host's kernel

`coder` has passwordless `sudo`, and a normal booth has no user-namespace remapping, so root in the
booth is root to the host's kernel. Every layer in §2 holds against it today, but a kernel or
runtime bug would land as host root. §5 covers what changes that: `--sudo false`, rootless Podman,
or a Kata VM.

---

## 2. What the isolation gets right (verified)

These held up under active testing and you can rely on them for a **normal** booth (no `--dind`):

- **No host filesystem access** beyond explicit mounts — no upward traversal out of a mount.
- **No raw disk access.** Even as container-root, the cgroup device filter blocks opening host
  block devices, and `mount` is blocked (no `CAP_SYS_ADMIN`).
- **Separate PID and network namespaces** — no host processes visible, and no host service bound to
  `127.0.0.1` reachable. Services on other host addresses, other booths and the LAN *are* reachable;
  see [What a booth can reach](#network-reach).
- **Masked `/proc` and `/sys`** — `kcore` (host memory), `sysrq`, keys, etc. are neutralized.
- **No Docker socket** mounted — no "control the daemon → own the host" path.

The container boundary itself is sound. The remaining risk is in **configuration** (§3) and in
**opting into privilege** (§4).

**How confident is "safe"?** In hands-on testing, code running in a **normal booth** — no `--dind`,
no manually added `--privileged` — **could not break out to the host**. Every filesystem, device,
and namespace escape attempt was blocked. That is strong, empirically-backed assurance, but it is
**not a 100% guarantee**: a normal booth has no user-namespace remapping (§5), so a future kernel or
runtime bug could still be catastrophic. Treat a normal booth as **safe to a good degree** for code
you're cautious about — and add the §5 hardening if the stakes are high.

**The contrast with `--dind` is stark.** The moment you add `--dind`, breakout becomes **easy** (§4)
— a privileged sidecar hands back everything the normal booth withholds. The difference between
"held up under attack" and "trivially escapable" is exactly that one flag. Choose it deliberately.

---

## 3. Convenience mounts: your secrets inside the booth

CodingBooth's `--select` features and `run-args` can add bind mounts that pull host secrets into the
booth. Common examples:

```toml
# .booth/config.toml  (run-args)
"-v", "~/.claude/.credentials.json:/etc/cb-home/.claude/.credentials.json:ro"  # +credential    ← LIVE OAUTH TOKENS
"-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro"                        # +settings-cache ← paths, usage, account metadata
"-v", "~/.config/pip:/etc/cb-home-seed/.config/pip:ro"                          # +pip-config    ← pip config (may embed index creds)
"-v", "$XDG_RUNTIME_DIR/pulse/native:/run/pulse/native:ro"                      # host-audio     ← the host's sound server
```

| Mount | Contains | Severity if untrusted code runs |
|-------|----------|---------------------------------|
| `~/.claude/.credentials.json` | **Live access + refresh OAuth tokens** | 🔴 Critical — account takeover until tokens are revoked |
| `~/.claude.json` | Host directory layout, per-project usage, account identity | 🟡 Recon / privacy |
| `~/.config/pip` | pip index URLs — may embed registry credentials | 🟡 Depends on contents |
| `$XDG_RUNTIME_DIR/pulse/native` | The host's sound server (PulseAudio / PipeWire) — **including the microphone**; `:ro` does not limit what the socket can do | 🟡 Privacy — can record audio |
| `$XDG_RUNTIME_DIR/pipewire-0` (`host-audio+jack`) | PipeWire itself — audio, microphones, and cameras / screen-share streams it carries | 🟡 Privacy — can record audio and possibly video |

A refresh token is the worst case: it is long-lived and mints new access tokens, so a copied refresh
token outlives the session.

**Guidance**

- **Trusted booth** (your own code/prompts): convenience mounts are fine — the thing reading the
  credential is *you*, who already has it. Keep `+credential` if you want it.
- **Untrusted booth** (cloned repos, third-party agents, MCP servers, code under review, anything
  unattended): **do not mount real credentials.** Instead:
  1. Log in *inside* the booth with a **throwaway/secondary account** — the in-booth `~/.claude`
     persists to `.booth/cache/home/coder/.claude` (inside the project), isolated from your host
     account. See **[booth cache](BOOTH_LOCALCACHE.md)**.
  2. Or use the booth for non-credentialed work.
  3. Or pass a **scoped, short-lived token** via an env var instead of the full credential file.

To drop a mount, remove the matching `+feature` from your `--select`, or delete the corresponding
`-v` line from `.booth/config.toml`'s `run-args`. (Config is read-only inside the booth by default,
so edit it on the host.)

---

<a id="dind"></a>

## 4. Docker-in-Docker (`--dind`): a host-escape path by design

`--dind` is powerful and legitimate — but it is a **privileged capability, not a security
boundary**. Treat enabling it as equivalent to granting host-root-level trust to whatever runs in
the booth.

### Architecture

`--dind` does **not** mount the host's `/var/run/docker.sock` (good — that would be instant
game-over). Instead it launches a **sidecar** container and the booth talks to it over TCP:

```
Host Docker
├── DinD sidecar  (docker:dind, started with --privileged)  → daemon on :2375 (no TLS, no auth)
└── Booth         shares the sidecar's network namespace → DOCKER_HOST=tcp://localhost:2375
```

The **host** Docker daemon is never exposed, and containers you start are invisible to the host
daemon. That part is good. What it does **not** change: the sidecar runs **`--privileged`**, created
by the *host* daemon, so it holds all capabilities and sees the **host's `/dev`** (including the raw
disks).

### Why it's an escape (verified on a real host)

Everything that blocks the raw-disk escape in a normal booth (no `CAP_SYS_ADMIN`, the cgroup device
filter, `mount` denied) is **handed back** the moment a privileged daemon is reachable:

1. Any code in the booth reaches the DinD daemon at `tcp://localhost:2375` — **unauthenticated**.
2. It launches a **`--privileged`** container on that daemon. Because the sidecar is host-privileged,
   that nested container inherits the **host's** block devices in `/dev` (confirmed: a nested
   privileged `alpine` lists `/dev/nvme*`) and the full host capability set.
3. From there it can **read/write the entire host filesystem as root** (e.g. `debugfs` against the
   host root device reads `/etc/shadow` and root-only files) **and execute code on the host as
   root** — the writable, non-namespaced `kernel.core_pattern`, `cap_sys_module` + `insmod`, or
   persistence writes (`~/.ssh/authorized_keys`, cron, systemd units) all reach the shared host
   kernel/disk.

> **Bottom line:** in a `--dind` booth the trust boundary is not the container — it is "can this code
> reach `:2375`?", and by design it always can. **Never enable `--dind` in a booth that runs
> untrusted code, and don't count on `--egress` in a `--dind` booth** (code that can start a privileged
> container can also rewrite the firewall — see **[Egress](implementations/EGRESS.md)**).

### Booth asks before it starts one of these

Because a `--dind` booth is host-root-equivalent, booth does **not** start one silently. The same
goes for `run-args` that give the booth a way out on their own (below). Before anything is built or
started, booth lists what it found — each setting with what untrusted code could do with it, and a
link to its section here — and asks:

```
⚠️  This booth has settings that let code inside it reach the host:

  - --dind (privileged Docker-in-Docker sidecar)
      Untrusted code in the booth could drive the privileged Docker daemon and run commands on the host as root.
      https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md#dind

  This only matters if the booth runs code you do not trust.
  If you trust what it runs, go ahead.

Start this booth? [y/N]:
```

The warning is about **untrusted** code. Every one of these settings has legitimate uses, and for
code you trust the answer is simply yes. Not every kind leads to root: a writable data mount or
`--network=host` is reported for what it is (see the table below), not as host root.

- **The default is no.** Anything but `y` / `yes` aborts, and nothing has been started.
- **Only what you type after the question counts.** Keys pressed before it — a stray Enter while
  the previous command was finishing — are thrown away. If the terminal returns no answer at all
  (a program before booth left it in a mode where reads do not wait), booth still refuses, but says
  so: `no answer could be read from the terminal`. Run `stty sane` (or open a new tab) and re-run.
- **It asks on the terminal itself** (`/dev/tty`), not on stdin, so a `booth shell --run` still
  prompts, and nothing piped into booth can answer for you.
- **No terminal** (CI, scripts, agents): booth **refuses and exits non-zero** unless the command line
  carries **`--dind-allowed`** (for `--dind`) or **`--privileged-allowed`** (for the run-args below).
  `booth shell --run` and `booth exec --run` accept both and pass them on to the booth they start.
- **The flags skip the question, not the warning.** With them, booth still prints the warning, ends
  it with `Allowed by --privileged-allowed — starting without asking.`, and starts. That is the way
  to run unattended (a hosted launcher, CI) and still leave the warning in the log.
- **Per run, never remembered.** There is no `config.toml` key and no environment variable for
  either flag, so a cloned repo, its config, or an env file can never pre-approve itself. The one
  exception is a `booth--restart` of a booth you already approved in the same session: it does not
  ask again unless something new turned up.
- **`--dryrun`** starts nothing, so it does not ask.
- **What booth asks about, and how it words it, depends on the engine** — see
  **[Container engines → Where a way out lands](BOOTH_ENGINES.md#where-a-way-out-lands)**:
  - **Rootless Podman** does not ask about `--dind` or `--privileged`-like run-args: the container's
    root is your own account, so they land as you, not as host root. It still asks about writable
    mounts (your home and dotfiles are code as you), `--network=host`, and engine sockets (a socket
    may belong to a rootful daemon). Rootful Podman — `sudo podman` — asks like Docker does.
  - **VM-based engines** (Docker Desktop on macOS, Windows, or Linux; Podman machine) ask about
    everything, but say "root in the engine's VM" rather than "root on the host": that VM shares
    your folders, and on Windows it is the WSL 2 VM that also runs your other WSL distros.
  - **Apple container** does not ask about flags it rejects anyway (`--privileged`, `--device`, …)
    or capabilities that stay in the booth's own VM; mounts and sockets still ask.

Answering yes does not make the booth safe; it only makes sure nobody gets host-root trust without
knowingly granting it. The rule stands: **don't say yes for untrusted code.**

**Starting the booth again warns again.** The settings are recorded on the container (the
`cb.security-warning` label). `booth start`, `booth restart`, and `booth shell --run` /
`booth exec --run` on a stopped booth print the same warning, ending with `This booth was created with
these settings.` — they do not ask, because consent was given when the booth was created. Attaching
`booth shell` / `booth exec` to a booth that is already running prints nothing. `exec` prints the
warning on stderr only, so its stdout stays clean for scripts.

**Check before you run: `booth print-security-warning`.** It takes the same options as a run, reads
the same `config.toml`, profiles, and templates, and prints the warning a run would show — nothing is
built, started, or asked. Exit `1` with the warning on stdout, or exit `0` with `No security
warning.` The `--*-allowed` flags do not change the result: it reports what the booth would get.

```bash
booth print-security-warning --dind      # exit 1 and the --dind warning
booth print-security-warning             # what this project's .booth/config.toml asks for
```

### What else booth asks about

`--dind` is not the only way to hand the booth host-level privilege. `run-args` and `common-args` (in
`config.toml`, from a template, or as extra options on the command line) are passed straight to the
container engine, and some of them are a way out on their own. Booth asks before starting a booth
with any of these. The warning groups them by what untrusted code could do, and links to the row:

| Kind | run-args | What untrusted code in the booth could do |
|------|----------|-------------------------------------------|
| <a id="kernel-access"></a>**kernel access** | `--privileged`; `--cap-add` `SYS_ADMIN`, `SYS_MODULE`, `SYS_RAWIO`, `DAC_READ_SEARCH`, `BPF`, `PERFMON`, `SYS_BOOT`, `MAC_ADMIN`, `MAC_OVERRIDE`, `ALL`; `--device <path>` (except `/dev/kvm`, `/dev/dri/…`, `/dev/net/tun`, `/dev/fuse`); `--device-cgroup-rule`; `--pid=host`, `--ipc=host`, `--userns=host`; `--security-opt` `seccomp=unconfined`, `apparmor=unconfined`, `label=disable` | reach the host's kernel, devices, or processes (mount, load modules, raw disk I/O, read any file) and from there get **root on the host** |
| <a id="engine-socket"></a>**engine socket** | a mount of `docker.sock`, `podman.sock`, or `containerd.sock` (even `:ro`) | tell the host's container engine to start a container that runs commands on the host **as root** |
| <a id="host-mounts"></a>**host mounts** | a **writable** mount of `/`, `/etc`, `/root`, `/boot`, `/dev`, `/proc`, `/sys`, `/run` (including `/run/media/…` drives), `/usr`, `/bin`, `/lib`, `/var/lib/docker`, `/var/lib/containers`, … | change the host files there, which the host system may rely on (for a data directory, the risk is mostly the data itself) |
| <a id="home-mounts"></a>**home mounts** | a **writable** mount of your home directory, `/home`, or a dotfile/dot-dir in it (`~/.bashrc`, `~/.ssh`, `~/.config`, `~/.m2`, …) | change files your account runs or loads — code **as you**, not root, e.g. the next time you log in or build |
| <a id="host-network"></a>**host network** | `--network=host` | reach every service listening on the host, including ones bound only to localhost |

**A booth on a git worktree does not ask either.** A worktree's `.git` is a file pointing into the
main clone's `.git/`, outside the workspace, so booth also mounts that folder, writable, at
`/opt/codingbooth/git/<repo>/.git`. That is the same exposure as a booth on a plain clone, whose `.git/` is inside the
workspace mount: code in the booth can change refs and objects, and write `.git/hooks/` or
`.git/config`, which run as you the next time you use git on the host. Treat it like any other
writable workspace (§1). Submodules are not mounted this way, so git does not work in a booth
opened on a submodule.

Git finds a worktree through absolute host paths in one-line pointer files: the worktree's `.git`
file, and each record's `.git/worktrees/<id>/gitdir`. Booth covers each of them in the container
with a generated read-only file that points within the booth, so no host path appears there —
not even the empty folders leading to the repository, which would look like your home directory.
`/opt/codingbooth/git` itself is a read-only tmpfs, so even root in the booth cannot write there.
The host's own pointer files do not change. The generated ones are kept in the workspace's
`.booth/.tmp/git-pointers/` when it has a `.booth/`, mounted read-only over itself in the booth so
code there cannot edit them in place; otherwise in `~/.cache/codingbooth/git-pointers/` (or under
`$XDG_CACHE_HOME`), whose folders are removed once their workspace folder is gone.

In a booth on any repository that has worktrees, the main clone too, each other worktree gets a
read-only one-line `.git` file under `/opt/codingbooth/git/<repo>/worktrees/<id>/` (just that file,
not the worktree), so its record does not look stale and an in-booth `git worktree prune` does not
drop it. A worktree that `git worktree add` makes in the booth is written with the booth's paths.
The next booth on the same folder writes the host's paths back, if that worktree is inside the
workspace (one outside it exists only in the container). Booth also writes one file per worktree
into the repository's own `.git/worktrees/<id>/` (`cb-host-path`, the worktree's host path),
from which it undoes a `git worktree repair` an older booth ran.

On Apple container and on a Windows host, booth keeps the older layout: the main clone's `.git`
and each worktree's `.git` file are mounted at their host paths, so those paths appear in the
booth.

Read-only mounts (`:ro`), like the credential seeds templates add, do not ask — they leak what they
contain (§3) but do not let the booth run anything on the host. A `--device` the host does not have
does not ask either: booth drops it before the run. Nor do the four devices the table excepts —
`/dev/kvm`, `/dev/dri/…`, `/dev/net/tun` and `/dev/fuse` — because none is a way out: each lets the
booth use one kernel feature (run a VM, render on the GPU, make a network interface, mount a FUSE
file system), and does not reach the host's files, processes, or other devices. They do widen
what a kernel bug in that feature could be used for, the same exposure your own account already has
— a desktop login can usually open `/dev/kvm` and `/dev/dri` itself — so asking every Android or
GPU booth to say "yes" would only teach people to say it without reading.

> ⚠️ **This is a list of known ways out, not a proof of safety.** `run-args` is a raw passthrough, and
> there are other ways to hurt yourself with it. Treat `run-args` as a trusted, advanced surface —
> the same trust rule as `--dind`: read what a cloned repo puts there before you run it.

<a id="dind-isolation"></a>

### Contain it: `--dind-isolation kata` (experimental)

> **Experimental.** Verified on one host (below) and by a container test (`tests/basic/test040`, which
> skips where Kata cannot run); its interface may change. To put the **booth itself** in a VM, see
> [`--booth-isolation kata`](#booth-isolation).

`--dind-isolation kata` runs the DinD sidecar in its own **[Kata Containers](https://katacontainers.io/)
VM** instead of `--privileged` on this machine. The booth itself stays an ordinary container: same
`coder` user, same mounts, same devices. Only the daemon moves behind a VM boundary, so a way out of
it lands **in that VM, not on this machine**. The VM shares nothing from this machine — the sidecar
mounts no host folder.

```bash
./booth --dind-isolation              # bare = kata; implies --dind
./booth --dind-isolation=kata
```

Or `dind-isolation = "kata"` in `.booth/config.toml`, `CB_DIND_ISOLATION=kata`, the **DinD
Isolation** field in `booth config`, or the `dind+kata` template extension, which also sizes the VM
(`booth config --select 'dind+kata'` for 4 GB and 2 CPUs, `'dind+kata:8g,4'` to choose). It does not ask for consent: there is nothing on this machine
for it to reach. Every run prints an `experimental` warning.

**What the escape test shows.** The same test as above — a nested `--privileged alpine` on the
sidecar's daemon — sees only the VM's own devices (`ram*`, its storage loop disk, Kata's read-only
`pmem0` guest image) and the guest kernel; **none of the host's `nvme*` / `sd*` disks**, which the
plain `--dind` sidecar exposes.

#### What it gains — and what it does not

It turns `--dind` from *"code in the booth can get root on this machine"* into *"code in the booth
can get root in a throwaway VM"*.

**Gains**

- **The documented escape is closed.** A `--privileged` container started through the daemon no
  longer gets this machine's disks, kernel modules, `core_pattern` or files. The daemon and everything
  it runs are inside a VM that has none of your folders.
- **A kernel exploit lands in a throwaway kernel.** The sidecar's containers share the VM's guest
  kernel, not this machine's; getting out takes a hypervisor escape as well.
- **`--dind` is usable with code you do not fully trust** — AI agents, a cloned repo, its
  dependencies — that need Docker for builds, tests or compose. With no consent prompt, unattended
  runs (CI, scripts, agents) need no `--dind-allowed`.
- **The booth costs nothing.** It stays an ordinary container: same `coder` uid, mounts and devices
  (what rootless Docker could not keep), and the host needs no sysctl and no Docker restart.

**Not protected** — these are the same as in any booth:

- **The booth itself.** Code in it still reaches the code folder (read-write), every credential you
  mount in (`dind-example` and `kind-example` mount `~/.claude/.credentials.json` and
  `~/.docker/config.json`), and the network. Kata does nothing for those; see §3.
- **The network.** The VM has full outbound access and can reach your LAN and `host.docker.internal`.
  This isolates the host's files and kernel, not its network — and `--egress` cannot be combined with
  it yet.
- **The hypervisor.** A QEMU/KVM escape would still reach the host. Rarer and much harder, not
  impossible.

**Costs**

- Linux only, with KVM and Kata installed (about 1 GB).
- A VM per booth: 2 GB of memory by default (`--dind-vm-memory`), and a slower start.
- Networking is different (see below): `localhost` works through a forwarder, and `booth expose list`
  is incomplete.
- Experimental, and it tracks a moving target: Kata's shims and defaults change between releases.

**When to use it.** Docker in a booth that runs code you do not fully trust: a real gain. A trusted
project of your own: optional overhead. On macOS and Windows it is not available (Docker Desktop's
single VM, which shares your home folder, is the weaker setup there — see
[Engines](BOOTH_ENGINES.md#where-a-way-out-lands)).

#### What it needs

| Need | How to check / get it |
| --- | --- |
| Linux, x86_64 or arm64 | Not Docker Desktop (macOS, Windows, or Docker Desktop for Linux) — its VM has no Kata. Podman falls back to its plain sidecar (below). |
| Hardware virtualisation | `ls -l /dev/kvm`. VT-x / AMD-V on in the BIOS; inside a cloud VM, nested virtualisation. |
| Docker Engine, rootful | Docker 23+ runs a containerd shim by name, so **no `daemon.json` change and no Docker restart**. |
| Kata Containers | Unpack the static release and put its shim on PATH (below). About 1 GB on disk. |

```bash
# Kata 4.x (the static release ships the Rust shim)
V=4.3.1
curl -fLO https://github.com/kata-containers/kata-containers/releases/download/$V/kata-static-$V-amd64.tar.zst
zstd -dc kata-static-$V-amd64.tar.zst | sudo tar -x -C /
sudo ln -sf /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2

# Proof it works: the kernel differs from the host's
docker run --rm --runtime io.containerd.kata.v2 alpine uname -r
```

booth checks the engine, Linux, Docker Desktop, `/dev/kvm` and the shim at the very start of the run,
before it asks, builds or creates anything.

#### When this machine cannot run Kata

A project can ask for Kata in its committed `.booth/config.toml` (`dind-isolation = "kata"`) and still
open for a teammate on macOS, Windows, Docker Desktop, or Linux without KVM or Kata. There the booth
**falls back to the plain, privileged `--dind` sidecar — never silently**:

```
⚠️ ⚠️ ⚠️  DIND ISOLATION (KATA) WAS ASKED FOR, BUT IS NOT AVAILABLE ON THIS MACHINE  ⚠️ ⚠️ ⚠️
    --dind-isolation kata needs Linux (Docker Engine with KVM); this is darwin. ...
    Going on runs the PLAIN, PRIVILEGED DinD sidecar instead — not a Kata VM.
    Booth asks before it does; --dind-allowed goes on without asking.
```

followed by the usual `--dind` warning and [consent](#booth-asks-before-it-starts-one-of-these):

| | What happens |
| --- | --- |
| With a terminal | the banner and warning, then `Start this booth? [y/N]` |
| No terminal (CI, scripts, agents) | refused, naming `--dind-allowed` — so a job that counted on Kata fails closed |
| `--dind-allowed` on the command line | the banner and warning, then it starts the plain sidecar without asking |

The same applies whether Kata was asked for by flag, `CB_DIND_ISOLATION` or `config.toml`.
`booth print-security-warning` reports the fallback the same way, and `--dryrun` shows what this
machine would run. (On rootless Podman the plain sidecar lands as your own account, so there, as for
any `--dind`, booth does not ask — the banner still shows.) The first run builds a small local image, `codingbooth-dind-kata:1` (`docker:dind` plus
`e2fsprogs`).

#### What changes inside the booth

A VM has its own network, so the booth can no longer share the sidecar's network namespace:

| | `--dind` | `--dind-isolation kata` |
| --- | --- | --- |
| Booth's network | the sidecar's namespace | the DinD network, beside the sidecar |
| `DOCKER_HOST` | `tcp://localhost:2375` | `tcp://<booth>-<port>-dind:2375` (also in `BOOTH_DIND_HOST`) |
| `localhost:<port>` → a container the sidecar runs | shared namespace | forwarded by `booth--dind-forward` (below) |
| Booth's own port | published by the sidecar | published by the booth |
| `run-args` `-p` | published by the sidecar | still published by the sidecar |

`booth--dind-forward` (started by the startup hook `56-cb-dind-forward--startup.sh`) puts each port
back on the booth's loopback: the `run-args` publishes at once, and every port a container in the
sidecar publishes on all interfaces, as it appears (checked every 2 s). So `docker run -p 8080:80 nginx` then `curl localhost:8080` works
as with plain `--dind`. It needs a base image built with that hook; on an older one, use
`$BOOTH_DIND_HOST:<port>`.

Inside the sidecar's VM, four things are done differently from `docker:dind`, each because Kata
requires it:

- **No `--privileged`.** Kata's `--privileged` passes the host's devices into the VM — the very
  exposure this mode removes — so the sidecar gets `--cap-add ALL` and unconfined
  AppArmor/seccomp/system paths instead, all of which apply only inside the VM, and remounts its
  `/sys` and `/sys/fs/cgroup` read-write.
- **DNS.** Docker's embedded resolver (`127.0.0.11`) does not answer inside the VM, so the sidecar
  gets this machine's upstream nameservers.
- **`/dev/kmsg`.** A non-privileged container has none, so neither does a `--privileged` container
  the sidecar starts — and kubelet (kind's node) will not start without it. The sidecar creates the
  guest kernel's.
- **Storage.** overlayfs cannot run on virtio-fs, through which every volume reaches the VM, so the
  sidecar's `/var/lib/docker` is a sparse 64 GB ext4 file, loop-mounted in the VM, removed with it.

#### Sizing the VM

Kata's default VM is **2 GB and 1 CPU**, shared by everything the sidecar runs. Raise it with
`--dind-vm-memory 8g` / `--dind-vm-cpus 4` (also `dind-vm-memory` / `dind-vm-cpus`,
`CB_DIND_VM_MEMORY` / `CB_DIND_VM_CPUS`, and the TUI). They are ignored, with a note, without
`--dind-isolation`.

#### How to tell it is running in Kata

```bash
# On the host: the sidecar's runtime and its VM process
docker inspect -f '{{.HostConfig.Runtime}}' <booth>-<port>-dind     # io.containerd.kata.v2
pgrep -af qemu-system | grep -c kata                                 # one VM per Kata container

# In the booth
echo "$BOOTH_DIND_ISOLATION"                          # kata
docker run --rm alpine uname -r                       # Kata's guest kernel, not the host's
docker run --rm --privileged alpine sh -c 'ls /dev | grep -E "^(nvme|sd)"'   # nothing
```

#### Known limits (experimental)

- **Not with `--egress`** yet (refused).
- **A port published on the sidecar's loopback only** (`127.0.0.1:...`) cannot be forwarded: publish
  on all interfaces. kind's default does bind its API server to loopback; `kind-example` sets
  `networking.apiServerAddress: "0.0.0.0"`, so it works unchanged (verified: cluster Ready, `kubectl`
  through `localhost:6443`, the hello service on `localhost:30081`). Give kind more room than the
  default 2 GB VM for real workloads (`--dind-vm-memory 4g`).
- **A port the booth itself listens on** keeps the booth's listener; the sidecar's container on the
  same port is then reachable only at `$BOOTH_DIND_HOST:<port>`.
- **`booth expose list`** reports the booth's own ports; the run-args ports the sidecar publishes are
  not listed for a Kata booth.
- Startup is slower (a VM boots, and the first run builds the image and formats the disk).

### What does *not* fix it

Don't rely on these — they don't close the escape:

- **TLS/auth on `:2375`** — the booth holds the credentials anyway.
- **`:ro` mounts** — irrelevant to the daemon path.
- **`--cap-drop=MKNOD` on the booth** — the *sidecar* is the privileged one, and privileged re-grants it.
- **Network-isolating the port** — the booth shares the sidecar's network namespace.

### Genuine mitigations (each has a real cost — you choose)

- **Don't run untrusted code in a `--dind` booth.** This is the reliable control.
- **Rootless DinD is *not* a drop-in fix.** Switching the sidecar to `docker:dind-rootless` would
  confine nested privileged containers, but rootless `dockerd` can only **start** if the host permits
  unprivileged user namespaces. On Ubuntu 23.10+ that is **off by default**
  (`kernel.apparmor_restrict_unprivileged_userns=1`), and the only ways to enable it are to relax a
  **host-wide** control (`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`, which
  re-enables unprivileged userns for *every* process) or to install a permissive host AppArmor
  profile. Either way it requires host-admin action and a security trade-off elsewhere — so it is a
  deliberate host-configuration decision, not a free win.
- **VM-isolated sidecar: `--dind-isolation kata`** (experimental) — the sidecar runs in its own
  Kata VM, so even a sidecar/kernel escape lands in a disposable VM, not the real host. Strongest
  option; needs KVM and Kata installed. See **[Contain it](#dind-isolation)** above.
- **Rootless Podman** (`--engine podman`, see **[Podman support](PODMAN_SUPPORT.md)**) — container
  root is your own account, so a breakout lands as you, not as host root. (Docker's `userns-remap`
  and rootless mode would do the same, but CodingBooth does not support them — it cannot keep project
  files owned by you there.)
- **An authorization plugin** on the sidecar daemon that denies `--privileged` / host-device
  requests — belt-and-suspenders even on a privileged sidecar.

---

## 5. Defense-in-depth for any booth

Even without `--dind`, there is currently **no last line of defense** if a kernel gap were found:
the booth runs with `uid_map = 0 0 4294967295` (no user-namespace remapping), so container-root maps
to host-root. Every other layer holds today, but you can shrink the blast radius:

- **Turn off `sudo`: `--sudo false`** (or the `no-sudo` template, `sudo = false` in
  `.booth/config.toml`). Setup and startup scripts still run with `sudo`, which is revoked after them.
  Code in the booth then cannot become root, so it loses root's capabilities, cannot use an exploit
  that starts from root, and cannot leave a root-owned setuid file in the code folder
  ([above](#code-folder)). It does not help against a kernel exploit that works from an ordinary
  user, the network, or the code folder's other risks.
- **Use rootless Podman** so container-root ≠ host-root (Docker's `userns-remap` and rootless mode
  are not supported by CodingBooth). Root in the booth is then *your account* on the host. A kernel
  escape lands as you, not as root, and a privileged `--dind` sidecar is privileged only inside your
  user namespace. Your account still holds a lot (`~/.ssh`, shell start-up files, tokens). The code
  folder and network risks are unchanged, and a rootless Podman booth can still reach Docker booths
  ([table](#network-reach)). Podman support is experimental.
- **Drop `CAP_MKNOD`** (`--cap-drop=MKNOD` via `run-args`) — a dev booth never needs to create device
  nodes, and it removes the first step of a disk-escape chain.
- **Scope mounts to the project directory.** Avoid mounts that reach up into `~` for anything but
  explicitly needed files.
- **Use `--egress`** to restrict outbound connections when running third-party or untrusted
  dependencies (not a boundary in a `--dind` booth). See **[Egress](implementations/EGRESS.md)**.
- **Put the booth in its own VM: `--booth-isolation kata`** (experimental) — container-root is then
  root in a throwaway VM with its own kernel. See **[below](#booth-isolation)**.

<a id="isolation-levels"></a>
### Choosing a level

Each level keeps what the one before it gives. Pick by how much you trust the code, prompts and
skills that will run.

| Level | Flags | What it adds | What is still open |
| --- | --- | --- | --- |
| 1. Normal booth | none | Host filesystem, devices and processes are out of reach (§2) | The [code folder](#code-folder), the [network](#network-reach), root to the host's kernel |
| 2. No root | `--sudo false` | No root, no root capabilities, no setuid-root files | The code folder, the network, kernel bugs reachable from an ordinary user |
| 3. A VM | `--booth-isolation kata` | A kernel exploit lands in a throwaway guest kernel | The code folder; the network, **including other booths** |
| 4. A VM with filtered traffic | `--booth-isolation kata --egress --sudo false` | No route to other booths, host services or the LAN, in or out; outbound traffic only to the allowlist | The code folder, anything you mount in, a hypervisor escape |

Level 1 is fine for trusted work. For code you do not trust, use level 4 where Kata runs (Linux,
Docker Engine, KVM), and treat the code folder as untrusted afterwards either way. Rootless Podman is
a separate axis: it turns "root on the host" into "your account" at levels 1 to 3, but changes
nothing else.

<a id="booth-isolation"></a>

### Put the booth in a VM: `--booth-isolation kata` (experimental)

> **Experimental.** Verified on one host and by a container test (`tests/basic/test045`, which skips
> where Kata cannot run); its interface may change.

`--booth-isolation kata` runs the **booth itself** in its own
**[Kata Containers](https://katacontainers.io/) VM**. It is the same booth — same image, same `coder`
user with your uid, the code folder mounted read-write, the same front door — started with Kata's
runtime instead of runc. A way out of the container, or a kernel exploit, lands in that VM's guest
kernel, **not on this machine**.

```bash
./booth --booth-isolation                  # bare = kata
export CB_BOOTH_ISOLATION=kata             # every booth from this shell (and the test suites)
```

Or `booth-isolation = "kata"` in `.booth/config.toml`. `--booth-isolation none` turns a configured
one off for a run. Every run prints an `experimental` warning.

**With `--dind`, the sidecar goes into Kata too** (as if `--dind-isolation kata` were given): a
privileged sidecar on this machine, reachable from the booth, would undo the VM. So a
`--booth-isolation --dind` booth needs no consent prompt.

#### What it gains — and what it does not

**Gains**

- **Container-root is root in a VM.** Without user-namespace remapping, root in an ordinary booth is
  root on this machine's kernel (§5 above). In a Kata booth it is root in a guest kernel that has none
  of this machine's devices, disks or processes.
- **A kernel exploit lands in a throwaway kernel.** Getting out takes a hypervisor escape as well.
- **Nothing else changes for the work inside.** Builds, editors, desktops and the front door behave
  as in any booth.

**Not protected**

- **What you mount in.** The code folder is shared into the VM (virtio-fs) read-write, as are any
  convenience mounts (§3). Code in the booth can change them, as you. Root in the VM can also leave
  a root-owned setuid file there ([code folder](#code-folder)); add `--sudo false`.
- **The network.** The VM has full outbound access and reaches your LAN and host services on
  `0.0.0.0`. It is still on Docker's default bridge, so **other booths reach its UI and it reaches
  theirs** ([table](#network-reach)). `--egress` closes all of this ([below](#booth-isolation-egress)).
- **The hypervisor.** A QEMU/KVM escape would still reach the host.

#### What it needs

The same as [`--dind-isolation kata`](#dind-isolation): Linux, Docker Engine (not Docker Desktop),
`/dev/kvm`, and Kata's shim on `PATH`. booth checks them at the very start of the run. Where they
are missing (macOS, Windows, Docker Desktop, no KVM or Kata), the booth runs as an **ordinary
container** — never silently:

```
⚠️ ⚠️ ⚠️  BOOTH ISOLATION (KATA) WAS ASKED FOR, BUT IS NOT AVAILABLE ON THIS MACHINE  ⚠️ ⚠️ ⚠️
    --booth-isolation kata needs Linux (Docker Engine with KVM); this is darwin. ...
    Going on as an ORDINARY CONTAINER instead — not a Kata VM.
```

It does not ask first: an ordinary container is what every other booth is.

On **engine apple** there is no banner: Apple container already runs each booth in a VM of its own,
so there is nothing for Kata to add. The run says so in one line and goes on as usual:

```
ℹ️  --booth-isolation: engine apple already runs each booth in its own VM; nothing more to do.
```

#### Sizing the VM

`--vm-memory` / `--vm-cpus` (also `vm-memory` / `vm-cpus`, `CB_VM_MEMORY` / `CB_VM_CPUS`) — the same
settings that size the booth's VM on Apple container. The default is **4 GB and 2 CPUs**; Kata's own
default (2 GB, 1 CPU) is too small to build most projects. booth sets them through Kata's
annotations, because `-m` / `--cpus` would only add to Kata's default VM.

With `--dind`, the sidecar's VM gets the same default (4 GB, 2 CPUs) — a plain sidecar would have had
all of this machine, and Kata's 2 GB / 1 CPU cannot hold a Compose stack such as Appwrite's.
`--dind-vm-memory` / `--dind-vm-cpus` size it instead.

#### What booth does differently for a Kata booth

- **DNS:** the booth gets a `resolv.conf` naming this machine's real resolvers (from
  `/run/systemd/resolve/resolv.conf` or `/etc/resolv.conf`, loopback entries dropped). Docker's
  embedded DNS (`127.0.0.11`), which a booth on a user-defined network such as the DinD network is
  given, does not answer inside the VM.
- **Open-file limit:** the booth gets Docker Engine's usual `nofile=1024:524288` (`--ulimit`), as
  does a Kata DinD sidecar. Kata would otherwise start it with 2^30, and programs that size a table
  by that limit run out of memory in the VM — each Erlang VM took 1.4 GB. A `--ulimit nofile=…`
  of your own in run-args wins.
- **The DinD sidecar by name:** with `--dind`, the sidecar's name is added to the booth's
  `/etc/hosts` (`--add-host`), since that embedded DNS is what normally resolves it.
- **Refused:** run-args a VM cannot honour — `--privileged` (Kata then tries to pass every host
  device into the VM, and fails), `--gpus`, `--device /dev/kvm` (Kata's guest kernels are built
  without KVM, so there is no nested virtualisation: the node is there but dead, and the Android
  emulator would wait on it until it times out), and `--network`/`--pid`/`--ipc=host` (there is no
  host namespace to join from another kernel). Remove them, or run without `--booth-isolation`.
- **Refused: host sockets.** A bind mount whose source is a socket on this machine — the PulseAudio
  and PipeWire sockets of the `host-audio` template, an engine socket — cannot cross into the VM
  (virtio-fs shares files, not sockets); Kata would fail the run with a bare "Input/output error".
  booth refuses it up front and names the socket.

<a id="booth-isolation-egress"></a>
#### With `--egress`

An ordinary egress booth shares the egress sidecar's network namespace, where Envoy listens on
`127.0.0.1:15001`. A Kata booth has a kernel of its own and cannot share it, so instead:

- the booth stands **alone on an internal network** (`docker network create --internal`): no
  gateway, no route out. Nothing leaves it except through the proxy, and there is no firewall rule
  inside the booth for its root to undo;
- the egress sidecar is the **gateway**: it is on that network and on an ordinary one, Envoy runs
  in its namespace as usual, and it publishes the booth's ports and DNATs them on to the booth. It
  forwards nothing else — its `FORWARD` policy drops all but those connections and their replies;
- in the booth, `127.0.0.1:15001` is carried to the gateway's Envoy, so `HTTP_PROXY` and
  everything that names the proxy are as in any egress booth.

`--egress` together with `--dind` is still refused with `--booth-isolation`: there the booth shares
the DinD sidecar's network.

#### How to tell it is running in Kata

```bash
docker inspect -f '{{.HostConfig.Runtime}}' <booth>    # io.containerd.kata.v2
./booth exec -- 'echo $BOOTH_ISOLATION; uname -r'     # kata, and Kata's guest kernel
```

#### Known limits (experimental)

- **Not with `--egress` and `--dind` together** (refused); `--egress` alone works.
- **Not with host audio** (`host-audio`): its sockets are refused, see above.
- **No Android emulator:** `--device /dev/kvm` is refused, see above.
- **Other devices** passed with `--device` are not refused, but may not work inside the VM.
- Startup is slower: a VM boots for each booth.

### Keep the booth's trust store current

A booth trusts the certificate authorities its **image was built with**, and there is more than one
list inside it. The system bundle (`ca-certificates`) serves curl, git, apt and Go programs, but
pip uses its own vendored copy of certifi, and Node, code-server, Bun, Deno, uv, Java and Electron
apps each bundle their own list too. A patched host does not change any of them, and rebuilding a
project's image does not either while the build cache and the skip-unchanged fingerprint keep the
old layers.

When a CA is distrusted, as with the **eMudhra CA key compromise of October 2026**:

1. **Move to a CodingBooth release that has the fix** (see the [CHANGELOG](CHANGELOG.md)). An old
   pinned version keeps its old image; booths still on 0.77.x (Ubuntu 24.04) trust the compromised
   eMudhra chains through curl itself.
2. **Rebuild the project image fresh.** `booth --pull` fetches the base image again and skips the
   unchanged-build check; with a new release's base image, every layer above it is rebuilt. On the
   same base image the build cache still keeps each `setup` step's old download (pip, Node, a
   JDK), so clear it first with `docker builder prune`, or rebuild once with
   `build-args = ["--no-cache"]` in `.booth/config.toml`.
3. **Check it** from inside the booth. The incident's test hosts must fail with a certificate error:

   ```bash
   curl https://dv-g3b-emudhra.we-have-a-problem.com/
   curl https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
   ```

   Repeat with each runtime the project uses (`pip download`, `node`, `java`), because each has its
   own list. `tests/manual/run-emudhra-live-manual-test.sh` runs all of them against an image.

Booth itself takes care of the ones it controls: the images install `ca-certificates` from the live
archive (never a stale snapshot), the `python` setup holds pip and certifi above the fixed versions,
code-server's bundled Node verifies against the system store, and the CLI is built with a Go
toolchain that refuses the compromised keys.

---

## 6. Incident response: a mounted secret was exposed

If untrusted code may have read a mounted credential:

1. **Revoke immediately.** For Claude: `claude logout` then `claude login` on a trusted machine.
   Logout invalidates the access **and** refresh tokens **server-side** — a copied token becomes
   useless even though the file may still exist.
2. **Remove the mount before re-authenticating.** Otherwise the fresh tokens get re-mounted and
   re-exposed on the next booth start. Order matters: fix config → then re-auth.
3. **Note the bind-mount inode quirk:** a *running* booth keeps showing the old credential file
   (single-file bind mounts pin the inode) until restart. Harmless once tokens are revoked, but don't
   mistake "old file still visible" for "logout didn't work."
4. **Rotate anything else that was mounted** (pip index creds, SSH keys, cloud tokens, etc.).
5. If the exposure was in a **`--dind`** booth, assume **host compromise** is possible: rotate host
   credentials, check `~/.ssh/authorized_keys`, cron, and systemd units for unexpected entries.

---

## 7. Checklist before launching a booth

- [ ] Will untrusted code run here? If yes → **no real-credential mounts**, **no `--dind`**.
- [ ] What's in `run-args`? Every `-v ~/...` mount is a host secret/path exposed inside. Privileged
      flags (`--privileged`, `--cap-add SYS_ADMIN`, `--device`, `--pid=host`, engine-socket mounts)
      are host-root-equivalent; booth asks before starting them (or needs `--privileged-allowed`
      with no terminal) — only say yes for trusted code. `booth print-security-warning` lists them
      without starting anything.
- [ ] Using a throwaway account for untrusted work? (in-booth login persists to `.booth/cache`)
- [ ] `--dind` only if the code here is trusted? (DinD = privileged = host-escape path; never with
      untrusted code). Booth asks every run — or needs `--dind-allowed` with no terminal.
- [ ] Want extra hardening? `--sudo false` / rootless Podman / `CAP_MKNOD` dropped / `--egress`
      filter / `--booth-isolation kata`. See [Choosing a level](#isolation-levels).
- [ ] Are other booths running with work you care about? An untrusted booth can open a shell in
      them unless it runs with `--egress` ([network](#network-reach)).
- [ ] After untrusted code ran: no git, build tool or editor in that folder on the host until it is
      reviewed; recover from a fresh clone ([code folder](#code-folder)).
- [ ] Know how to revoke each mounted credential if it leaks?
- [ ] After any suspected exposure: revoked tokens → fixed config → re-authed?

---

## Related documentation

- **[README — Security Considerations](../README.md#security-considerations)** — summary table.
- **[Egress](implementations/EGRESS.md)** — egress filtering with Envoy + iptables.
- **[Container engines](BOOTH_ENGINES.md)** — where a way out lands on each engine.
- **[Podman support](PODMAN_SUPPORT.md)** — rootful and rootless Podman.
- **[Docker-in-Docker](implementations/DIND.md)** — how `--dind` works internally.
- **[booth home](BOOTH_HOME.md)** / **[booth cache](BOOTH_LOCALCACHE.md)** — where in-booth
  credentials and state persist.
</content>
</invoke>
