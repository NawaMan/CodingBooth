#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java:17/android-sdk+emulator+kvm"

boothfile="$prj/.booth/Boothfile"
configtoml="$prj/.booth/config.toml"
kvmstartup="$prj/.booth/startups/45-android-sdk-kvm--startup.sh"

# Params land as args, so a rebuild cannot silently move the toolchain.
assert-line "$boothfile" "arg ANDROID_CMDLINE_TOOLS=" "11076708" "ANDROID_CMDLINE_TOOLS arg"
assert-line "$boothfile" "arg ANDROID_API="           "34"       "ANDROID_API arg"
assert-line "$boothfile" "arg ANDROID_BUILD_TOOLS="   "34.0.0"   "ANDROID_BUILD_TOOLS arg"

# The SDK line carries its flags, and the emulator reuses the SDK's API param
# rather than declaring a second one that could drift.
assert-line "$boothfile" 'setup android-sdk --cmdline-tools ${ANDROID_CMDLINE_TOOLS} --api ${ANDROID_API} --build-tools ${ANDROID_BUILD_TOOLS}' "" "android-sdk setup line"
assert-line "$boothfile" 'setup android-emulator --api ${ANDROID_API} --tag ${ANDROID_IMAGE_TAG} --abi ${ANDROID_IMAGE_ABI}' "" "android-emulator setup line"

# java is a `requires`, so selecting android-sdk must pull the JDK in ahead of it.
assert-line "$boothfile" 'setup jdk ${JDK_VERSION} ${JDK_VENDOR}' "" "jdk setup line (required by android-sdk)"

# The kvm extension is run-args plus a startup hook; nothing host-specific.
# In particular there is no --group-add: the host's kvm gid never reaches the
# generated config, because the startup hook fixes the mode container-side.
assert-line "$configtoml" 'run-args = ' '["--device", "/dev/kvm"]' "kvm run-args device"
assert-line "$kvmstartup"  '  elif sudo -n chmod 0666 /dev/kvm 2>/dev/null; then' "" "kvm startup relaxes the device mode"

if grep -q -- "--group-add" "$configtoml"; then
    echo "  ❌ config.toml carries a host-specific --group-add"
    exit 1
fi

finally
