# Compatibility

CodingBooth runs on Linux, macOS and Windows hosts, on x86_64 (amd64) and arm64 CPUs. Almost
everything in the catalog works the same on all of them. This page lists the exceptions: the
setups, templates and features that do not work, or only partly work, on some platform — and why.

Anything not listed here works on amd64 and arm64, and on every host. That includes the tools that
come prebuilt from [CodingBoothPrebuilt](https://github.com/NawaMan/CodingBoothPrebuilt) (GHC,
IHaskell, OCaml, Nim, Goose, hlint, ormolu, sqls, evcxr, Scratch, Excalidraw), which publishes both CPUs.

On Apple Silicon, Docker builds arm64 images, so everything in the arm64 table applies there too.

## CPU: arm64

Apple Silicon Macs, AWS Graviton, Raspberry Pi 5, and other 64-bit Arm machines.

| Setup / template | On arm64 | Why |
| --- | --- | --- |
| `android-sdk` (+`emulator`, +`kvm`) | Skipped with a warning; the booth still builds | Google publishes the SDK tools and the emulator for linux x86_64 only |
| `flutter+android` | Skipped (`flutter` and `flutter+linux-desktop` work) | It needs the Android SDK, above |
| `wails+android` | Skipped (`wails` itself works) | The Android NDK is published for linux x86_64 only |
| `google-chrome` | Not installed; a stub command explains why | Google ships no linux/arm64 Chrome. Use `chromium`. |
| `heidisql` | Skipped | HeidiSQL publishes a `.deb` for amd64 only |
| `kotlin` with Kotlin/Native | Fails | JetBrains ships Kotlin/Native for linux-x86_64 only. Kotlin/JVM works. |
| `puppeteer` | Partly: drives the system Chromium | Chrome for Testing has no linux-arm64 build |
| `selenium` | Partly: Debian's Chromium, and a browser version pin is ignored | Same reason |
| `elm` 0.19.1 | Works, from a community aarch64 build | Upstream has no arm64 binary for 0.19.1; 0.19.2 and later are official |
| `cuda` | Server-class Arm64 (SBSA) only, not Jetson | NVIDIA's repository layout |
| `lsp+haskell` (HLS) | May reject the installed GHC ("GHC ABIs don't match") | The arm64 HLS binary can be built against a different GHC build |
| `--apt-snapshot` / `APT_SNAPSHOT` | The pin is ignored | arm64 packages come from ports.ubuntu.com, which has no snapshots |

## Host: Windows

Docker Desktop, with the `booth` wrapper in Git Bash or WSL.

| Feature | On Windows | Why |
| --- | --- | --- |
| A booth started from a git worktree | The booth starts, but git does not work inside it; booth warns | The worktree's `.git` mirror cannot be made on Windows |
| File permissions: `:mode` mount suffixes, seeds, cache folders, `.booth/` copies | Modes are not applied | Windows has no Unix permission bits |
| Credential mounts (for example Claude Code's) | No guarantee that the credential stays mode 0600 | Same reason |
| `booth logs -f` | Ctrl+C may not stop the follow inside the booth | A native Windows process cannot get SIGINT |
| `--dind-isolation kata` / `dind+kata` | Not available; booth falls back to the plain sidecar and says so | Docker Desktop's VM has no Kata |
| `android-sdk+kvm` (hardware-accelerated emulator) | Only under WSL2 with `/dev/kvm`; otherwise slow software emulation | Needs KVM |
| `cuda` (running GPU code) | Only through WSL2 with NVIDIA's driver | Needs the NVIDIA Container Toolkit |

## Host: macOS

| Feature | On macOS | Why |
| --- | --- | --- |
| `--dind-isolation kata` / `dind+kata` | Not available | Needs Linux with Docker Engine (not Docker Desktop), `/dev/kvm` and Kata |
| `android-sdk+kvm` | No hardware acceleration | No `/dev/kvm` |
| `cuda` (running GPU code) | Not available | No NVIDIA GPU passthrough |
| Everything in the [arm64](#cpu-arm64) table | Same as arm64, on Apple Silicon | Docker builds arm64 images there |
| `wails` iOS builds | Not from a booth | Needs macOS with Xcode, not a Linux container |

## Container engine

Docker is the supported engine. See [Container engines](BOOTH_ENGINES.md).

| Feature | Engine | Status |
| --- | --- | --- |
| `--dind` (the `dind` template) | Apple container | Refused for now; with no engine chosen, the run goes to Docker or Podman ([details](CONTAINER_SUPPORT.md)) |
| `--egress` (allowlist, Envoy, read-only) | Apple container | Same |
| `--dind-isolation kata` | Podman | Falls back to the plain sidecar ([details](BOOTH_SECURITY.md#contain-it---dind-isolation-kata-experimental)) |
| Any booth | Linux rootless Docker, or userns-remap | Not supported: use rootful Docker Engine, or Docker Desktop |

## Hardware

| Feature | Needs |
| --- | --- |
| `--dind-isolation kata` | Linux, `/dev/kvm`, and Kata Containers' `containerd-shim-kata-v2` on `PATH` |
| Fast Android emulator | A `/dev/kvm` the booth user can open |
| `cuda`, to run GPU code (compiling works anywhere) | An NVIDIA GPU, its driver, and the NVIDIA Container Toolkit |

Not listed: setups that refuse CPUs other than amd64 and arm64 — CodingBooth does not support
those CPUs at all.
