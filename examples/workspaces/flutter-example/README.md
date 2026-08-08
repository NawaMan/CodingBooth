# Flutter example — a counter app, compiled and served from a booth

A small, real Flutter app (`booth_counter/`) and the booth that builds it. It exists to show three
things: that `setup flutter` produces a working SDK, that the web target needs nothing else, and
that the result is reachable from the browser through the booth's own web pane.

The app is `flutter create` output with a purpose-written `lib/main.dart` — a counter, a button,
and one line of text. Nothing clever; the point is the toolchain around it.

## What the booth has

```
setup flutter --version ${FLUTTER_VERSION}
setup flutter-code-extension
```

That is the whole `.booth/Boothfile`. `flutter` deliberately `requires` nothing, so this booth has
no JDK and no Android SDK in it — `flutter build web` does not need them, and making everyone pay
several gigabytes for a target they may not use would be the wrong default. The
`flutter-code-extension` line is the auto-selected `+vscode-ext`; on the `base` variant it skips
itself cleanly, and on `codeserver`/desktop variants it installs Dart and Flutter language support.

`FLUTTER_VERSION` defaults to `latest`, which resolves against Google's release manifest at build
time. Pin it if you want the toolchain held still:

```bash
booth config . --select "flutter:3.44.9"
```

Both `.booth/Boothfile` and `.booth/config.toml` are `booth config` output, not hand-written, and
ship with the `.booth/.generated` fingerprint — so `booth config` opens this example in its TUI
instead of guarding it as hand-authored.

## Run it

```bash
booth
```

Then, inside the booth:

```bash
cd booth_counter
flutter test          # runs the widget test
flutter build web     # compiles to build/web/main.dart.js
```

To see it in a browser, serve it from inside the booth and open it through the web pane:

```bash
cd booth_counter
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

`--web-hostname 0.0.0.0` matters: bound to `localhost` the server is unreachable from outside the
container, so the pane shows nothing. With it, browse to `/proxy/8080/` on the booth's port and the
counter is there. There is no Chrome in this booth, which is why the device is `web-server` and not
`chrome` — `flutter devices` will show only the one.

## Building an APK instead

The app was created with `--platforms=web,android`, so the Android scaffolding is already in
`booth_counter/android/`. It needs the Android toolchain, which is a separate selection:

```bash
booth config . --select "flutter+android"
booth
# then, inside:
cd booth_counter && flutter build apk --debug
```

That pulls in the Android SDK and, through it, a JDK. The first `flutter build apk` takes several
minutes, because Gradle downloads the NDK and CMake the Android build needs; later builds do not.
The `+android` extension is what makes that possible at all — it installs the platform Flutter
compiles against (36, read from the Flutter SDK, not the Android SDK's default of 34) and leaves
the SDK tree writable so Gradle can fetch those components.

To *run* the app rather than only build it, add the emulator as well —
`booth config . --select "flutter+android/android-sdk+emulator+kvm"` — and start it with
`cb-android-emulator` before `flutter run`. See `../android-example` for what the emulator side of
that looks like on its own.

## Tests

```bash
./.cb-tests/test001-flutter--on-host.sh
```

Starts the booth and runs the in-booth suite:

| Test | Asserts |
| --- | --- |
| `inBooth-test001-flutter-sdk` | `flutter`/`dart` resolve in a **non-login** shell, `flutter --version` runs, `dart` compiles and runs a program, and the SDK cache is writable by the booth user |
| `inBooth-test002-build-web` | `flutter build web` produces `main.dart.js`, and this app's own UI string is in it |
| `inBooth-test003-widget-test` | `flutter test` drives the framework — a headless render, a tap, a rebuild |

Two of those are guarding specific traps rather than being thorough for its own sake. The non-login
shell is the one `booth -- ./script.sh` actually gets, and it never reads `/etc/profile.d`, so a
tool wired only through the profile passes interactively and fails in every script. The writable
check is there because `booth-entry` remaps the booth user's UID to the host user's at container
start — a build-time `chown` matches only by luck, and the failure would appear on some machines
and not others.

## Note on architecture

Google publishes the Flutter SDK for linux x86_64 only — across their whole release manifest there
has never been an arm64 stable Linux build. On arm64 the booth still starts, but the setup warns
and skips, and this example cannot build in it.
