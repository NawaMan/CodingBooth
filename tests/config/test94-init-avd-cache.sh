#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java:17/android-sdk+emulator+avd-cache"

boothfile="$prj/.booth/Boothfile"
cachedir="$prj/.booth/cache/home/coder/.android"

# The extension is cache-only: it must not add a build step, or every booth that
# wants persistence would also pay a rebuild.
assert-line "$boothfile" 'setup android-emulator --api ${ANDROID_API} --tag ${ANDROID_IMAGE_TAG} --abi ${ANDROID_IMAGE_ABI}' "" "emulator setup line still present"

if [[ -d "$cachedir" ]]; then
    echo "Test: cache dir for ~/.android is created ......................... PASSED"
else
    echo "Test: cache dir for ~/.android is created ......................... FAILED"
    echo "  expected directory: $cachedir"
    exit 1
fi

# .booth/cache/ must stay out of git — this one grows to gigabytes.
if git -C "$prj" check-ignore -q .booth/cache 2>/dev/null || grep -qE '(^|/)cache/?$' "$prj/.booth/.gitignore" 2>/dev/null; then
    echo "Test: .booth/cache is gitignored .................................. PASSED"
else
    echo "Test: .booth/cache is gitignored .................................. SKIPPED (no repo/gitignore in fixture)"
fi

finally
