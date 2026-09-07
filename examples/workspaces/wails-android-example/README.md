# Wails Android example — the same counter, as an APK, on the emulator

The Android sibling of [`wails-example`](../wails-example). Same Go backend and
Vite frontend; this booth selects `wails+android` plus the Android emulator
and KVM, on **xfce**, so `just build` produces a debug APK and `just run`
installs it on an AVD.

Wails v3 compiles the existing `main.go` to `libwails.so` with the NDK
(`GOOS=android`) and a small Java host loads it. There is no separate mobile
codebase. Mobile is still experimental in v3.

The default `wails-example` stays desktop-sized on purpose: the Android SDK,
NDK and system image are several extra gigabytes. This folder is that cost,
isolated.

## What the booth has

```
setup go ${GO_VERSION}
setup nodejs ${NODE_VERSION}
setup wails --version ${WAILS_VERSION}
setup android-sdk …
setup android-emulator …
setup wails-android
```

`variant = "xfce"` so the emulator has a desktop to draw on. `+android` pulls
a JDK and installs NDK **26.3.11579264** plus **API 35** (Wails'
`compileSdk 35`). `+emulator` adds the emulator binary and an AOSP system
image; `+kvm` passes `/dev/kvm` so the AVD is usable (~20s boot vs ~4 minutes
in software). Google publishes the SDK/emulator for linux x86_64 only — the
config forces `--platform linux/amd64` (no-op on a real amd64 host). On arm64
the NDK setup skips and no APK can be built natively; see Architecture below.

Both `.booth/Boothfile` and `.booth/config.toml` are `booth config` output,
not hand-written, and ship with the `.booth/.generated` fingerprint. The
copies of `wails--setup.sh` and `wails-android--setup.sh` under
`.booth/setups/` let this example run against a released base image that
does not yet ship those scripts.

## Run it

```bash
cd examples/workspaces/wails-android-example
booth
```

Then, inside the booth:

```bash
just --list
just doctor            # wails3 doctor + sdkmanager --list_installed
just build             # debug APK → bin/booth-counter.apk
just emulator          # AVD window on XFCE (or `just emulator -- -no-window`)
just run               # build if needed, boot AVD, install and launch
just desktop           # optional: native Linux GUI of the same app
```

The first image build is the long one (SDK + NDK + system image). Later
`just build` only pays Gradle/NDK compile.

The XFCE desktop also has an **Android Emulator** icon (`cb-android-emulator`).
It creates an AVD on first run and picks KVM vs `-accel off` for you.

Without `/dev/kvm` the emulator does **not** fall back on its own — it
refuses (`x86_64 emulation currently requires hardware acceleration!`).
`cb-android-emulator` passes `-accel off` in that case. Selecting `+kvm` is
safe on any host: if the device is missing, the booth still starts and the
device is dropped with a warning.

The AVD is not persisted (`~/.android` is not in the local cache). Add
`android-sdk+emulator+kvm+avd-cache` if you want the device to survive a
restart — see [`android-example`](../android-example).

iOS is not this example. It needs macOS + full Xcode. On a Mac:
`wails3 task ios:run`.

## Architecture note

Same constraint as [`android-example`](../android-example): Google's platform
tools, build tools and emulator are **linux x86_64 only**. `build-args` and
`run-args` force `--platform ${CB_ANDROID_PLATFORM:-linux/amd64}`. Building
an APK that way on Apple Silicon works (slow first rebuild). **The emulator
does not** — it crashes under Docker Desktop's translation. Use a real
device (`adb`) or an amd64 Linux/Windows host with KVM. Set
`CB_ANDROID_PLATFORM=linux/arm64` on an arm64 CI runner to skip the QEMU
image rebuild.

## Layout

Same as `wails-example`: `main.go` + `backend/` + `frontend/` + Wails
`build/` (including `build/android/`). Output is `bin/booth-counter.apk`,
not `build/`. See that example's README for what `build/` is.

## Tests

```bash
./.cb-tests/test001-wails-android--on-host.sh
```

| Test | Asserts |
| --- | --- |
| `inBooth-test001-wails-android-sdk` | `wails3`, `sdkmanager`, NDK 26.3, `cb-android-emulator` |
| `inBooth-test002-build-apk` | `just build` produces `bin/booth-counter.apk` with a ZIP header and this app's UI string |
| `inBooth-test003-emulator` | boots the AVD, installs the APK, MainActivity reaches the foreground — skipped under CI or without KVM unless `CB_ANDROID_EMULATOR_TEST=1` |
