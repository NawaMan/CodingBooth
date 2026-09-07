#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- 1. Wails pulls Go and Node, and does not drag in Docker ---------------
run booth config $prj --no-tui --select "wails"

boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"

assert-line "$boothfile" "arg WAILS_VERSION=" "latest" "WAILS_VERSION arg"
assert-line "$boothfile" 'setup wails --version ${WAILS_VERSION}' "" "wails setup line"

if ! grep -qE '^setup go ' "$boothfile"; then
    echo "  ❌ go was not pulled in by requires"
    exit 1
fi
if ! grep -qE '^setup nodejs ' "$boothfile"; then
    echo "  ❌ nodejs was not pulled in by requires"
    exit 1
fi

if grep -qE '^setup dind' "$boothfile"; then
    echo "  ❌ a bare 'wails' selection pulled in Docker-in-Docker"
    exit 1
fi
if grep -qE '^dind' "$config"; then
    echo "  ❌ a bare 'wails' selection set dind = true"
    exit 1
fi
if ! grep -q 'WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1' "$config"; then
    echo "  ❌ config.toml is missing the WebKitGTK sandbox disable (needed in a booth)"
    exit 1
fi

# --- 2. The version pin lands ----------------------------------------------
run booth config $prj --no-tui --overwrite --select "wails:v3.0.0-beta.16"
assert-line "$boothfile" "arg WAILS_VERSION=" "v3.0.0-beta.16" "WAILS_VERSION pin"

# --- 3. +cross pulls DinD, and still has wails -----------------------------
run booth config $prj --no-tui --overwrite --select "wails+cross"
assert-line "$boothfile" 'setup wails --version ${WAILS_VERSION}' "" "wails still present with +cross"
assert-line "$boothfile" "setup dind" "" "dind (required by wails+cross)"
assert-line "$config" "dind = " "true" "config.toml dind flag"

# --- 4. +android pulls the SDK (and a JDK), not Docker ---------------------
run booth config $prj --no-tui --overwrite --select "wails+android"
assert-line "$boothfile" 'setup wails --version ${WAILS_VERSION}' "" "wails still present with +android"
assert-line "$boothfile" "setup wails-android" "" "wails-android setup"
assert-line "$boothfile" 'setup android-sdk --cmdline-tools ${ANDROID_CMDLINE_TOOLS} --api ${ANDROID_API} --build-tools ${ANDROID_BUILD_TOOLS}' "" "android-sdk (required by wails+android)"
assert-line "$boothfile" 'setup jdk ${JDK_VERSION} ${JDK_VENDOR}' "" "jdk (pulled by android-sdk → java)"
if grep -qE '^setup dind' "$boothfile"; then
    echo "  ❌ wails+android pulled Docker-in-Docker"
    exit 1
fi

finally
