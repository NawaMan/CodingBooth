#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- 1. Flutter on its own -------------------------------------------------
# The default target is web, which needs nothing but the SDK, so a bare
# selection must not drag in a JDK or the Android SDK.
run booth config $prj --no-tui --select "flutter"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg FLUTTER_VERSION=" "latest" "FLUTTER_VERSION arg"
assert-line "$boothfile" 'setup flutter --version ${FLUTTER_VERSION}' "" "flutter setup line"

# vscode-ext is auto-select, so it comes along without being asked for.
assert-line "$boothfile" 'setup flutter-code-extension' "" "flutter VS Code extension (auto-selected)"

if grep -qE '^setup (jdk|android-sdk)' "$boothfile"; then
    echo "  ❌ a bare 'flutter' selection pulled in the Android/JDK toolchain"
    exit 1
fi

# --- 2. The version pin lands ----------------------------------------------
run booth config $prj --no-tui --overwrite --select "flutter:3.41.9"
assert-line "$boothfile" "arg FLUTTER_VERSION=" "3.41.9" "FLUTTER_VERSION pin"

# --- 3. The Android target pulls its prerequisites, in order ----------------
# flutter-android reads both the Flutter SDK and the Android SDK, so it has to
# be emitted after both -- and android-sdk itself `requires` java, so selecting
# the extension must reach two levels down.
run booth config $prj --no-tui --overwrite --select "flutter+android"

assert-line "$boothfile" 'setup flutter-android' "" "flutter-android setup line"
assert-line "$boothfile" 'setup android-sdk --cmdline-tools ${ANDROID_CMDLINE_TOOLS} --api ${ANDROID_API} --build-tools ${ANDROID_BUILD_TOOLS}' "" "android-sdk (required by flutter+android)"
assert-line "$boothfile" 'setup jdk ${JDK_VERSION} ${JDK_VENDOR}' "" "jdk (required by android-sdk)"

# Ordering is the whole point of the 67 band: flutter-android configures a
# toolchain that does not exist until both of the others have run.
line_flutter=$(grep -n '^setup flutter --version' "$boothfile" | cut -d: -f1)
line_sdk=$(grep -n '^setup android-sdk '        "$boothfile" | cut -d: -f1)
line_wire=$(grep -n '^setup flutter-android'    "$boothfile" | cut -d: -f1)

if [[ -z "$line_flutter" || -z "$line_sdk" || -z "$line_wire" ]]; then
    echo "  ❌ could not locate all three setup lines to check ordering"
    exit 1
fi
if (( line_wire <= line_flutter || line_wire <= line_sdk )); then
    echo "  ❌ flutter-android (line $line_wire) must come after flutter ($line_flutter) and android-sdk ($line_sdk)"
    exit 1
fi

# --- 4. The Linux desktop target is independent of Android -----------------
run booth config $prj --no-tui --overwrite --select "flutter+linux-desktop"

assert-line "$boothfile" 'setup flutter-linux-desktop' "" "flutter-linux-desktop setup line"

if grep -qE '^setup (jdk|android-sdk|flutter-android)' "$boothfile"; then
    echo "  ❌ the linux-desktop target pulled in the Android toolchain"
    exit 1
fi

finally
