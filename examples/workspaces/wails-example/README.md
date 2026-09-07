# Wails example — a counter app, compiled (and cross-compiled) from a booth

A small, real [Wails v3](https://v3.wails.io/) app in this folder, and the booth
that builds it. It exists to show three things: that `setup wails` produces a
working `wails3` CLI plus the GTK 4 / WebKitGTK 6.0 headers Linux compilation
needs, that `wails3 build` produces a native Linux GUI binary, and that Windows
is a free cross-compile from the same booth (`wails3 build GOOS=windows`). The
example ships the **xfce** variant so the compiled app can be launched
(`just run`) instead of only built.

The number on screen lives in Go (`backend/`). The buttons in `frontend/` call
it. That is the whole app.

## Layout

```
main.go          Wails entry: window, embed, register the Go service
backend/        Go services the UI can call (the counter)
frontend/        Vite UI (TypeScript in this example)
frontend/dist/   bundled web UI, embedded into the binary (gitignored)
build/           this project's Wails config and packaging — see below
bin/             compiled binaries (gitignored). Wails' BIN_DIR.
Justfile         just build / just run / just build-all
.booth/          booth config (generated, not hand-written)
```

`main.go` has to stay at the project root because Go's embed cannot use `..`
(`//go:embed all:frontend/dist`). This is also what a user's own project looks
like: the Wails app *is* the workspace, next to `.booth/`. There is no extra
app folder.

## The `build/` folder

It is **this project's Wails config and packaging**, not the Wails tool, and
not the compiled app. `/opt/` and `/usr/local/bin/wails3` are the *installed*
CLI + GTK — shared, same for every app. `build/` is the opposite: `wails3 init`
copies it into the repo, it is checked in, and it is meant to be edited per
app. Same role as `frontend/`, or an Electron `electron-builder` folder.

| In `build/` | What it is |
| --- | --- |
| `config.yml` | **Where Wails is configured for this project** — name, identifier, version, `wails3 dev` |
| `Taskfile.yml` + `linux/` `darwin/` `windows/` `ios/` `android/` | Build recipes. `wails3 build` is a thin wrapper around these |
| `appicon.png`, `.desktop`, `Info.plist`, NSIS, DMG | Packaging assets, generated from `config.yml`, then yours to change |
| `docker/` | The `wails-cross` image this project uses for macOS / other-arch Linux |

The compiled app does **not** land here. That is `bin/`. `frontend/dist/` is
the web bundle Vite produces, which `main.go` embeds. Wails v3 docs say the
same: binaries go to `bin/`, there is no `build/bin/`.

Do **not** rename `build/` to `wails/` (or move it to `/opt/`). Wails hardcodes
the path: `wails3 dev -config ./build/config.yml`, the root `Taskfile.yml`
includes `./build/…`, and `wails3 update build-assets` writes `build/` again.
v2 used `wails.json` at the project root; v3 renamed that idea to
`build/config.yml` and put the platform files next to it. The folder name is
the confusing part — it sounds like output. The useful file to open is
`build/config.yml`.

## What the booth has

```
setup go ${GO_VERSION}
setup nodejs ${NODE_VERSION}
setup wails --version ${WAILS_VERSION}
```

Selecting `wails` pulls Go and Node.js (`requires`), plus their auto-selected VS Code
extensions. There is no Wails VS Code extension; Go and Node language support is what
the editor needs. `WAILS_VERSION` is pinned to `v3.0.0-beta.16` in this example so
the committed app matches the CLI that generated it. Use `latest` if you want the
setup to resolve the current tag at image-build time:

```bash
booth config . --variant xfce --select "wails"
```

Both `.booth/Boothfile` and `.booth/config.toml` are `booth config` output, not
hand-written, and ship with the `.booth/.generated` fingerprint. The copies of `wails--setup.sh` and `wails-android--setup.sh` under
`.booth/setups/` are what let this example run against a released base image
that does not yet ship those scripts.

## Run it

```bash
booth
```

Then, inside the booth:

```bash
just --list
just doctor            # wails3 doctor
just build             # native Linux GUI binary → bin/booth-counter
just build-windows     # Windows amd64 + arm64 .exe, no Docker
just build-macos       # darwin amd64 + arm64 (builds wails-cross if missing)
just build-all         # Linux + Windows + other-arch Linux + macOS
just build-android     # debug APK (needs +android — see Mobile)
just build-ios         # iOS simulator .app (needs a Mac + Xcode)
just run               # open the window on the XFCE desktop
```

`config.toml` sets `variant = "xfce"` (the `desktop-xfce` image). That is the display
`just run` needs; you do not have to pass `--variant` on the command line.

WebKitGTK 6.0 sandboxes its renderer with bubblewrap, which cannot create user
namespaces inside a booth. `just run` (and the template's `run-args`) set
`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` for that — the same class of
workaround as Chromium's `--no-sandbox` wrappers. GTK CSS parser warnings from
XFCE's GTK3 theme against GTK4 are noisy and harmless.

## A different frontend

Wails is Go plus a webview. The UI can be any web stack that builds to static
files in `frontend/dist/`:

| Frontend | How |
| --- | --- |
| Vanilla JS | drop TypeScript; keep Vite or even plain `index.html` |
| Vanilla TS | this example (`wails3 init -t vanilla`) |
| Svelte / React / Vue / Preact / Lit | `wails3 init -t svelte` (etc.), or replace `frontend/` |
| Java servlets | no — the backend is Go, not a JVM servlet container |

`wails3 init -t` lists the templates. Changing the frontend is replacing
`frontend/`; `main.go` and `backend/` stay.

## Cross-compiling macOS (and the other Linux arch)

Windows is CGO-free and needs no Docker. macOS, and Linux for the architecture
this booth is *not* running, need Wails' `wails-cross` image (Zig + the macOS
SDK, ~800MB). `just build-macos` and `just build-all` build that image on first
use — they do not skip.

The booth needs a working Docker daemon (DinD). This example's stock selection
is `wails` only; add `+cross` (or `dind`) if `docker info` fails:

```bash
booth config . --variant xfce --select "wails:v3.0.0-beta.16+cross"
booth
just build-all
```

The first run of `just build-all` / `just build-macos` is the long one
(`wails3 task setup:docker`). Later runs reuse the image. Two DinD
adjustments in this example, because Wails assumes a host Docker socket:

- `Dockerfile.cross` `COPY`s the Zig wrappers as real files instead of
  BuildKit `COPY <<EOF` heredocs (classic `docker build`). Ubuntu's
  `docker.io` client has no `buildx`; `DOCKER_BUILDKIT=1` is a hard error.
  Classic docker also cannot `COPY` *into* a foreign-platform image
  (containerd snapshotter), so `cross-docker.sh` inlines those files with
  `RUN` when it rebuilds `wails-cross:<arch>` under QEMU.
- Cross *runs* stream the project through a named volume (`cross-docker.sh`)
  instead of `-v /home/coder/code:/app`. The DinD daemon is a sibling
  container and cannot see the booth's bind mounts — that is why a stock
  `wails3 build GOOS=linux GOARCH=arm64` dies with `go.mod file not found`.
- Darwin/Windows-in-Docker use Zig in the host-arch `wails-cross` image.
  Other-arch Linux (amd64 booth → arm64 binary) needs that arch's gcc and
  GTK, so `cross-docker.sh` rebuilds `wails-cross:<arch>` under QEMU with
  `--build-arg TARGETPLATFORM=linux/<arch>` (classic docker does not set
  that itself, and an amd64 FROM then fails at `COPY` with "does not
  provide the specified platform"). Using the amd64 image's gcc for
  `GOARCH=arm64` fails assembling `gcc_arm64.S`. Cross-compiled macOS
  binaries are unsigned — Apple still wants a Mac (or a macOS CI runner)
  to sign before distribution.

## Mobile (iOS and Android)

Wails v3 compiles the **same** `main.go` and `frontend/` for phones. The
scaffolding is already under `build/ios/` and `build/android/` (`wails3 init`
writes it). Mobile is still experimental in v3, and the two platforms are not
equal in a Linux booth.

### Android — a separate example

Android needs a JDK, the Android SDK, and NDK 26.3. That is several extra
gigabytes, so it is **not** in this desktop booth. The sibling
[`wails-android-example`](../wails-android-example) selects `wails+android`
plus the emulator on xfce; `just build` produces `bin/booth-counter.apk` and
`just run` launches it on an AVD. Same `main.go`.

### iOS — not from this booth

iOS requires **macOS with full Xcode** (not the command-line tools). A Linux
booth cannot produce a `.app` / `.ipa`. `just build-ios` says so and exits.
On a Mac with Xcode: `wails3 task ios:run` (simulator) or
`wails3 task ios:package IOS_PLATFORM=device` (device, with a signing
identity). Same `main.go`.

## Tests

```bash
./.cb-tests/test001-wails--on-host.sh
```

Starts the booth and runs the in-booth suite:

| Test | Asserts |
| --- | --- |
| `inBooth-test001-wails-cli` | `wails3` resolves in a **non-login** shell, `wails3 version` reports v3, `wails3 doctor` sees GTK4/WebKitGTK 6.0, and `pkg-config` finds both |
| `inBooth-test002-build-linux` | `wails3 build` produces a Linux binary, and this app's own UI string is in it |
| `inBooth-test003-build-windows` | `wails3 build GOOS=windows` produces a PE `.exe` (MZ header) for Windows |
| `inBooth-test004-run-gui` | `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` is set, and `just run` stays up for 8s instead of SIGTRAPing on bubblewrap |

The non-login shell is the one `booth -- ./script.sh` actually gets. A CLI wired
only through GOPATH/bin via `/etc/profile.d` passes interactively and fails in
every script; the setup copies `wails3` to `/usr/local/bin` for that reason.
