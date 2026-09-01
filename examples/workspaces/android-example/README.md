# Android Example

This example builds a real, signed, installable Android APK inside a booth — with no Android Studio, no Gradle, and no network access at build time. `app/` holds a one-Activity app that displays a string; `build-apk.sh` drives the same pipeline the Android Gradle Plugin drives, one tool at a time: `aapt2 compile` → `aapt2 link` → `javac` → `d8` → `zipalign` → `apksigner`.

The quiet win here is that the Android toolchain is the classic "works on my machine" offender. It is a pile of separately versioned pieces — command-line tools, a platform, build-tools, each pinned by a build number nobody remembers — installed by an interactive SDK manager that will not proceed until licenses are accepted by hand. Reproducing a teammate's setup usually means an afternoon of `sdkmanager` archaeology. Here every version is an overridable build arg, licenses are accepted non-interactively at image build time, and the result is a byte-for-byte identical toolchain on every machine that builds the booth.

**Stack:** Android SDK (cmdline-tools 11076708, API 34, build-tools 34.0.0), Temurin JDK 17, Android emulator + AOSP system image, XFCE desktop

## Quick start

```bash
# 1. Launch the booth — opens an XFCE desktop in your browser
cd examples/workspaces/android-example
booth

# 2. In a terminal inside the booth — build the APK
./build-apk.sh
```

The APK lands at `build/hello.apk`, signed with a debug keystore generated on first build.

The booth runs the **XFCE desktop variant** so the emulator has somewhere to draw: you can start it with a window, watch the app launch, and click around it in the browser, rather than only driving it through `adb`. Building the APK needs none of that — it works fine from a plain terminal.

## What's included

| Component      | Details                                            |
|----------------|----------------------------------------------------|
| SDK            | cmdline-tools 11076708, platform-tools             |
| Platform       | API 34 (`android.jar`)                             |
| Build tools    | 34.0.0 — aapt2, d8, apksigner, zipalign            |
| JVM            | Temurin JDK 17                                     |
| Sample         | `app/` — one Activity, one string resource         |
| Build          | `build-apk.sh` — Gradle-free, offline              |
| App compat     | minSdk 24, targetSdk 34, versionCode 1             |

Override versions with the `ANDROID_API`, `ANDROID_BUILD_TOOLS`, `ANDROID_CMDLINE_TOOLS` and `JDK_VERSION` build args. The app's own compatibility is set by the `MIN_SDK`, `TARGET_SDK`, `VERSION_CODE` and `VERSION_NAME` environment variables read by `build-apk.sh`.

### Why minSdk/targetSdk are passed explicitly

`build-apk.sh` passes `--min-sdk-version` and `--target-sdk-version` to `aapt2 link`, and that is not decoration. Left undeclared, `targetSdkVersion` defaults to `minSdkVersion`, which defaults to **1** — and Android 14+ refuses to install any app targeting below API 23. The phone reports *"app isn't compatible with your phone"*, which sounds like a hardware or ABI mismatch and is neither; it is a deprecation floor.

The trap is that everything else looks healthy: the APK builds, signs, verifies under v1/v2/v3, and installs on the emulator without complaint. Only a real device rejects it. A normal Gradle project never hits this because the Android Gradle Plugin injects both values into the merged manifest from `build.gradle`; driving `aapt2` directly means supplying them yourself.

`.cb-tests/inBooth-test002-build-apk--in-booth.sh` asserts both are present and that `targetSdkVersion >= 23`.

### Build output

`build/` holds exactly one APK — `hello.apk`, the signed one, alongside apksigner's `hello.apk.idsig` v4 signature sidecar. The unsigned stages live in `build/intermediates/` (`unsigned.apk` straight out of `aapt2 link` + `d8`, and `aligned.apk` after `zipalign`). Neither can be installed: Android rejects an unsigned APK with `INSTALL_PARSE_FAILED_NO_CERTIFICATES`. Alignment must happen *before* signing, since `zipalign` rewrites entry offsets and would invalidate an existing signature.

## Why no Gradle

Gradle is what a real Android project uses, and nothing here stops you adding it (`booth config --select ...+gradle`). It is avoided in *this* example on purpose: on first run Gradle resolves the Android Gradle Plugin and its dependency tree from the network, so a green build would prove that the network worked, not that this booth's toolchain did. Driving the build tools directly keeps the example a genuine test of what the setup installed.

## Running the app in the emulator

The emulator and an AOSP system image are included, so this works out of the box — **except under CPU translation** (an amd64 booth forced with `--platform` on Apple Silicon). `cb-android-emulator` detects that case itself and refuses with a clear explanation and a pointer to `device-connect.sh` instead of crashing; see the [Architecture note](#architecture-note) for why, and the section below for testing on a real device instead.

### The easy way — the desktop icon

The booth's XFCE desktop carries an **Android Emulator** icon, also in the start menu under **Development**. It opens a terminal window and:

1. creates an AVD named `booth` from whichever system image is installed, the first time only;
2. picks the acceleration mode — hardware if `/dev/kvm` came through, otherwise `-accel off -gpu swiftshader_indirect`;
3. starts the emulator.

The same thing from a terminal is `cb-android-emulator`. Override the AVD name with `CB_AVD_NAME` and the device profile with `CB_AVD_DEVICE` (`avdmanager list device` for the options); anything else you pass is handed to `emulator` (`cb-android-emulator -no-window`).

The AVD is created against a real device profile (`pixel_6`) rather than `avdmanager`'s bare defaults, and that matters more than it sounds. With no profile you get `hw.mainKeys=yes`, which tells Android *"this device has physical Back/Home keys, so don't draw the on-screen navigation bar"* — and an emulator window has no physical keys, so there is then no way to press Back or Home at all, leaving you stuck inside whatever app is open. The defaults also give a 320×640 mdpi screen (smaller than any phone Android 14 expects) and `hw.keyboard=no`, so you can tap but not type. The launcher sets a real profile, an on-screen nav bar, a hardware keyboard, and names the software rasterizer explicitly since a booth has no GPU.

If you ever do get stuck in an app, `adb` is the way out:

```bash
adb shell input keyevent KEYCODE_HOME
adb shell am force-stop com.example.hello
cb-android-emulator-stop                  # shut the emulator down
```

### Keeping the device between sessions

As configured, `~/.android` is not persisted: the AVD is rebuilt on each booth start (a few seconds) and the device remembers nothing between sessions. Add the `avd-cache` extension to change that:

```bash
booth config --overwrite --variant xfce --select java:17/android-sdk+emulator+kvm+avd-cache
```

Then installed apps, settings and signed-in sessions survive a restart, and starting the emulator becomes a restore rather than a boot — 7–16s against 26–38s cold.

Two things to know before enabling it:

- **Stop with `cb-android-emulator-stop`.** The emulator does not reliably save a Quick Boot snapshot on its own way out, so `adb emu kill` — or just closing the booth — restores the previously saved state and silently discards the session. The stop command saves first.
- **It is about 2.8 GB** in `.booth/cache/`, mostly the RAM snapshot that makes the fast restore possible. That is local and gitignored, never committed; `rm -rf .booth/cache/home/coder/.android` reclaims it and gives you a clean device next start.

It is off by default for that size, which is why this example does not ship with it. See [Local Cache](../../../docs/BOOTH_LOCALCACHE.md).

The window can take a minute to appear — longer without KVM. Once it is up:

```bash
adb install -r build/hello.apk
adb shell monkey -p com.example.hello -c android.intent.category.LAUNCHER 1
```

### By hand

If you would rather drive it yourself:

```bash
avdmanager create avd -n dev -k "system-images;android-34;default;x86_64"
emulator -avd dev &                       # a window on the XFCE desktop
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 5; done
adb install -r build/hello.apk
adb shell monkey -p com.example.hello -c android.intent.category.LAUNCHER 1
```

`adb wait-for-device` returns as soon as the adb daemon *sees* the device, which is well before Android is usable — polling `sys.boot_completed` is the real gate, which is why the loop is there.

Add `-no-window` to run it headless and drive it purely through `adb`.

### About `+kvm` and speed

`+kvm` passes the host's `/dev/kvm` into the booth. It decides whether the emulator is pleasant or painful — measured in this example:

| | boot to `sys.boot_completed` |
|---|---|
| with `/dev/kvm` | **~20s** |
| `-accel off` (software) | **~258s** |

Without KVM the emulator does **not** quietly fall back — it refuses to start:

```
ERROR | x86_64 emulation currently requires hardware acceleration!
```

You have to ask for software emulation explicitly with `emulator -avd dev -accel off -gpu swiftshader_indirect`. It works — the APK installs and the app reaches the foreground exactly the same — it is just ~13× slower to boot.

**Selecting `+kvm` is safe on any host.** If `/dev/kvm` is not present — Docker Desktop on macOS, virtualization disabled in BIOS, a nested VM without nested virt — the booth still starts; the device is dropped with a warning and you fall back to `-accel off`. On Windows, Docker Desktop's WSL2 backend often *does* have `/dev/kvm` (Windows 11 enables nested virtualization by default); `ls /dev/kvm` inside WSL is the check.

Nothing host-specific is needed beyond the device itself. The node keeps its host `root:kvm 0660` ownership inside the container, which the booth user cannot open, so a startup hook relaxes the mode. `/dev` in a container is a private tmpfs, so that change never touches the host's device.

## Architecture note

Google publishes the Android platform tools, build tools and emulator for **linux x86_64 only**. To make this work out of the box on an arm64 host too (Apple Silicon, arm64 Linux), `.booth/config.toml` forces `--platform linux/amd64` on both `run-args` and `build-args` by default, via Docker's own amd64 emulation (Docker Desktop on Apple Silicon supports this through QEMU or the faster Rosetta option). On a real amd64 host (Linux or Windows, Intel/AMD) this is a no-op — it already matches, so nothing changes there. This has been verified end-to-end for `sdkmanager`/`aapt2`/`d8`/`apksigner` and a real `build-apk.sh` run; it's just a full, uncached rebuild the first time under emulation, so expect that one run to take several minutes longer than native. **Building an APK on Apple Silicon is fully solved this way, with no config changes needed.**

The default is driven by `${CB_ANDROID_PLATFORM:-linux/amd64}`, so set the `CB_ANDROID_PLATFORM` environment variable to override it — e.g. on an arm64 CI runner, `CB_ANDROID_PLATFORM=linux/arm64` cancels the forcing and restores the fast native skip (a few seconds) instead of paying for a full uncached emulated rebuild (which risks tripping `run-example-tests.sh`'s default 900s per-example timeout).

The Android **emulator** is a different story and does not work under this workaround, confirmed with three separate crashes across both Docker Desktop backends: under Rosetta it aborts on an unimplemented Linux syscall deep in the emulator's own virtualization runtime; under QEMU it aborts on `ptrace` (`ENOSYS`) inside the Qt GUI's sandboxing layer; and even when it doesn't hard-crash, it can hang resolving the virtual modem's IPv6 loopback address instead of booting. All three point at the same root cause — the emulator does its own low-level, hypervisor-style systems programming that neither translation backend fully implements — so this isn't a tunable setting, it's a hard wall. `+kvm` doesn't help either, since there is no real KVM to hand through on macOS. The emulator setup itself is still installed unconditionally, though — real amd64 Linux/Windows hosts can use it fine — but `cb-android-emulator` now detects this exact situation at launch and refuses with a clear explanation instead of crashing, rather than silently failing in a way that looks like a bug. When it finds `device-connect.sh` in the project (as this example does), it names it directly in that message so the real-device workaround below is one line away, not a README search. The detection doesn't try to name which backend is active — from inside the container Rosetta and QEMU are indistinguishable (`binfmt_misc` isn't exposed to the container under either one, and both wrap every process in an identically-named interpreter) — it just checks for Docker Desktop's Apple Silicon translation support being present at all, which was confirmed to hold under both backend settings.

**The practical workaround is a real device over Wi-Fi debugging instead of the emulator** — `adb` already works fine under the `--platform linux/amd64` build, and a real phone doesn't need any virtualization at all. From inside the booth:

```bash
./device-connect.sh <ip> <pairing-port> <pairing-code> [connect-port]
```

The one gotcha that cost real time working this out: Android's Wireless debugging screen has **two different ports for the same IP**, and it's easy to keep reading the wrong one. "Pair device with pairing code" opens a **temporary** pairing session (IP:port + a 6-digit code) that expires in roughly a minute — use it once with `adb pair`. The **main** Wireless debugging screen (the one you land on before tapping "Pair device...") separately shows a **persistent** `IP address & Port` line with no code next to it — that's the one `adb connect` actually uses, and it's stable across reconnects. Once paired, you don't need a new code again unless the booth container itself gets recreated (a `--run` without `--keep-alive` tears the container down afterward, which wipes its adb identity); use `codingbooth exec --run --keep-alive -- ...` to keep the pairing valid across multiple commands. After that:

```bash
adb connect <ip>:<persistent-port>
adb install -r build/hello.apk
adb shell monkey -p com.example.hello -c android.intent.category.LAUNCHER 1
```

This has been verified end-to-end: built, installed, and launched `hello.apk` on real hardware from a booth running on Apple Silicon, with `dumpsys activity activities` confirming `.MainActivity` as the resumed foreground activity.

## Tests

```bash
./run-automatic-on-host-test.sh
```

This launches the booth and runs `.cb-tests/inBooth-*` inside it: that the SDK tools resolve in a **non-login** shell, that they execute, and that `build-apk.sh` produces an APK carrying `classes.dex`, `resources.arsc`, a verifying signature, the expected package name, and a `minSdk`/`targetSdk` pair a real device will accept.

The emulator test runs too, wherever that is cheap — booting Android takes longer than everything
else here combined, so it turns itself off under CI and on a host without usable `/dev/kvm`. Turn it
off or force it on explicitly:

```bash
CB_ANDROID_EMULATOR_TEST=0 ./run-automatic-on-host-test.sh   # skip the emulator
CB_ANDROID_EMULATOR_TEST=1 ./run-automatic-on-host-test.sh   # run it regardless
```

That is `inBooth-test003`, which boots the emulator, `adb install`s the APK, launches it, and asserts `MainActivity` reached the foreground with nothing in the crash buffer — the one thing a successful build genuinely cannot tell you. It picks hardware acceleration or `-accel off` based on whether `/dev/kvm` is usable, so it runs either way.
