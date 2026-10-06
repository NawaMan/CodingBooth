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

**Mental model:** treat everything you mount into a booth, and every privilege you grant it, as
"handed to whatever runs inside." The question is never "is the booth isolated?" — it is **"what
did I put inside it, and do I trust the code that will run there?"**

---

## 2. What the isolation gets right (verified)

These held up under active testing and you can rely on them for a **normal** booth (no `--dind`):

- **No host filesystem access** beyond explicit mounts — no upward traversal out of a mount.
- **No raw disk access.** Even as container-root, the cgroup device filter blocks opening host
  block devices, and `mount` is blocked (no `CAP_SYS_ADMIN`).
- **Separate PID and network namespaces** — no host processes visible, no host sockets reachable.
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
```

| Mount | Contains | Severity if untrusted code runs |
|-------|----------|---------------------------------|
| `~/.claude/.credentials.json` | **Live access + refresh OAuth tokens** | 🔴 Critical — account takeover until tokens are revoked |
| `~/.claude.json` | Host directory layout, per-project usage, account identity | 🟡 Recon / privacy |
| `~/.config/pip` | pip index URLs — may embed registry credentials | 🟡 Depends on contents |

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
- **Rootless Podman does not ask.** There the container's root is your own account, so a breakout
  lands as you, not as host root. (Rootful Podman — `sudo podman` — asks like Docker does.) An engine
  socket mount still asks even under rootless Podman, because the socket may belong to a rootful
  daemon.

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

Read-only mounts (`:ro`), like the credential seeds templates add, do not ask — they leak what they
contain (§3) but do not let the booth run anything on the host. A `--device` the host does not have
does not ask either: booth drops it before the run.

> ⚠️ **This is a list of known ways out, not a proof of safety.** `run-args` is a raw passthrough, and
> there are other ways to hurt yourself with it. Treat `run-args` as a trusted, advanced surface —
> the same trust rule as `--dind`: read what a cloned repo puts there before you run it.

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
- **VM-isolated runtime** (Kata / Firecracker, or a VM-per-booth model) — even a sidecar/kernel
  escape lands in a disposable VM, not the real host. Strongest option; heaviest setup.
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

- **Use rootless Podman** so container-root ≠ host-root (Docker's `userns-remap` and rootless mode
  are not supported by CodingBooth).
- **Drop `CAP_MKNOD`** (`--cap-drop=MKNOD` via `run-args`) — a dev booth never needs to create device
  nodes, and it removes the first step of a disk-escape chain.
- **Reconsider passwordless `sudo`** inside the booth for untrusted work, or pair it with the above.
- **Scope mounts to the project directory.** Avoid mounts that reach up into `~` for anything but
  explicitly needed files.
- **Use `--egress`** to restrict outbound connections when running third-party or untrusted
  dependencies (not a boundary in a `--dind` booth). See **[Egress](implementations/EGRESS.md)**.

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
- [ ] Want extra hardening? rootless Podman / `CAP_MKNOD` dropped / `--egress` filter.
- [ ] Know how to revoke each mounted credential if it leaks?
- [ ] After any suspected exposure: revoked tokens → fixed config → re-authed?

---

## Related documentation

- **[README — Security Considerations](../README.md#security-considerations)** — summary table.
- **[Egress](implementations/EGRESS.md)** — egress filtering with Envoy + iptables.
- **[Podman support](PODMAN_SUPPORT.md)** — why rootless Podman does not ask.
- **[Docker-in-Docker](implementations/DIND.md)** — how `--dind` works internally.
- **[booth home](BOOTH_HOME.md)** / **[booth cache](BOOTH_LOCALCACHE.md)** — where in-booth
  credentials and state persist.
</content>
</invoke>
