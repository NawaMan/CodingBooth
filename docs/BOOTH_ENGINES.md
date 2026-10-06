# Container Engines

A booth is a container, and the container engine that runs it decides two things: which booth
features work, and **where a way out of the container lands** — on your machine as root, as your
own account, or inside a VM. This page is the overview. The details per engine live in:

- **[Podman support](PODMAN_SUPPORT.md)** — rootful and rootless Podman (experimental).
- **[Apple container support](CONTAINER_SUPPORT.md)** — the macOS-native `apple` engine
  (experimental).
- **[Security](BOOTH_SECURITY.md)** — what the security warning means and when booth asks.

## The engines

| Engine | Where containers run | Status |
| --- | --- | --- |
| **Docker Engine** (Linux, rootful) | directly on this machine, as root | supported |
| **Docker Desktop** — macOS, Windows, and Docker Desktop for Linux; also Colima, OrbStack, Rancher Desktop on macOS | in a Linux VM that shares some of this machine's folders | supported |
| **Podman, rootful** (`sudo podman`) | directly on this machine, as root | experimental |
| **Podman, rootless** | directly on this machine, as your account (the container's root is you) | experimental |
| **Podman machine** (macOS, Windows) | in a Linux VM, like Docker Desktop | experimental |
| **Apple container** (`apple`) | each container in its own lightweight VM | experimental |

Rootless Docker is not supported.

## Choosing one

`engine` is an ordinary setting: `--engine docker|podman|apple`, `CB_ENGINE=…`, or `engine = "…"`
in `.booth/config.toml` (or the "Container Engine" field in `booth config`). With nothing chosen,
booth picks Apple container when it is installed and running, then Docker, then Podman — see
[When you choose nothing](CONTAINER_SUPPORT.md#when-you-choose-nothing). Inside a booth,
`BOOTH_ENGINE` says which engine runs it.

## Features

| Feature | Docker | Podman | Apple container |
| --- | --- | --- | --- |
| `--dind` (Docker-in-Docker sidecar) | yes | experimental (nested Podman sidecar) | no — refused, or another engine is picked |
| `--egress` (filtered outbound network) | yes | yes | no — refused, or another engine is picked |
| `--privileged`, `--device`, `--pid/ipc/userns=host`, `--security-opt` run-args | yes | yes | no — the engine rejects them |
| Bind mounts (`-v`) | yes | yes | yes (single-file mounts have a quirk — see its page) |

## Where a way out lands

Some settings give code in the booth a way out of the container (the full list is in
[Security → What else booth asks about](BOOTH_SECURITY.md#what-else-booth-asks-about)). How far
that way out reaches depends on the engine, and the security warning says so:

| Setting | Docker Engine / rootful Podman (Linux) | Rootless Podman | VM-based (Docker Desktop, Podman machine) | Apple container |
| --- | --- | --- | --- | --- |
| `--dind`, `--privileged`, dangerous caps, devices, host namespaces | **root on this machine** | your own account only — **not reported** | **root in the VM**, which can change the folders the VM shares from this machine (your home) as you | rejected by the engine, or only the booth's own VM — **not reported** |
| engine socket mount (`docker.sock` …) | **root on this machine** | **root on this machine** if the socket is a rootful daemon's | root in the VM, as above | reported (the socket's daemon decides) |
| writable mount of a system path (`/etc`, `/run`, `/usr` …) | host files the system may rely on | only files your account can write | the shared files there, as you | the shared files there, as you |
| writable mount of your home or its dotfiles | **code as you** | **code as you** | **code as you** | **code as you** |
| `--network=host` | every service on this machine, localhost-only ones included | the same | the VM's network — and this machine's, where the engine forwards host networking | the same as VM-based |

Two things that change the picture on a VM-based engine:

- **The VM is not a wall around your files.** The VM shares folders from this machine — your home
  on macOS (`/Users`) and Linux, your drives on Windows — so root in the VM can change them, as
  you. That is why booth still asks on Docker Desktop; only the wording changes.
- **On Windows, the VM is the WSL 2 VM.** Docker Desktop runs in the same WSL 2 VM as your other
  WSL distros, so root there reaches those distros too, not only other containers. Booth detects
  this (running on Windows, or inside WSL with Docker Desktop) and says so.

How booth tells the cases apart:

- `--engine apple` → Apple container.
- Running on macOS or Windows → a VM (WSL 2 on Windows), for Docker and Podman alike.
- Podman on Linux run by a non-root user → rootless; by root → rootful.
- Docker on Linux → `docker info` is asked once, and only when there is something to warn about;
  `Docker Desktop` there means a VM (the WSL 2 VM when booth runs inside WSL). If `docker info`
  fails, booth assumes Docker Engine, which is the stronger warning.

Not yet verified on real hosts (the warning words them cautiously): whether a writable `/etc`
mount reaches macOS's `/private/etc` through Docker Desktop's default shares, how host networking
behaves on Docker Desktop with its opt-in host-networking setting, and `--network=host` on Apple
container.

## Related documentation

- **[Security](BOOTH_SECURITY.md)** — the warning, consent, and `booth print-security-warning`.
- **[Podman support](PODMAN_SUPPORT.md)** / **[Apple container support](CONTAINER_SUPPORT.md)**.
- **[booth run](BOOTH_RUN.md)** — `--engine` and the other run options.
