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

The emulator and an AOSP system image are included, so this works out of the box.

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

Google publishes the Android platform tools, build tools and emulator for **linux x86_64 only**. On an arm64 host (Apple Silicon, arm64 Linux) the booth still builds, but the SDK setup warns and skips, and no APK can be built in it.

## Tests

```bash
./run-automatic-on-host-test.sh
```

This launches the booth and runs `.cb-tests/inBooth-*` inside it: that the SDK tools resolve in a **non-login** shell, that they execute, and that `build-apk.sh` produces an APK carrying `classes.dex`, `resources.arsc`, a verifying signature, the expected package name, and a `minSdk`/`targetSdk` pair a real device will accept.

The emulator test is **opt-in**, because booting Android takes longer than everything else here combined:

```bash
CB_ANDROID_EMULATOR_TEST=1 ./run-automatic-on-host-test.sh
```

That adds `inBooth-test003`, which boots the emulator, `adb install`s the APK, launches it, and asserts `MainActivity` reached the foreground with nothing in the crash buffer — the one thing a successful build genuinely cannot tell you. It picks hardware acceleration or `-accel off` based on whether `/dev/kvm` is usable, so it runs either way.
