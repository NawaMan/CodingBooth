#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The kvm extension comes with android-sdk unless it is left out with ~kvm. The
# emulator is barely usable without /dev/kvm, and passing it costs nothing: it is
# not a device booth asks consent for, and a host without it drops it at start.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "android-sdk+emulator"

configtoml="$prj/.booth/config.toml"
kvmstartup="$prj/.booth/startups/45-android-sdk-kvm--startup.sh"

assert-line "$configtoml" 'run-args = ' '["--device", "/dev/kvm"]' "kvm run-args without asking for +kvm"
assert-line "$kvmstartup"  '  elif sudo -n chmod 0666 /dev/kvm 2>/dev/null; then' "" "kvm startup hook without asking for +kvm"

# ~kvm takes it out again, run-args and hook both.
run booth config $prj --no-tui --overwrite --select "android-sdk+emulator~kvm"
if grep -q -- "/dev/kvm" "$configtoml" || [[ -e "$kvmstartup" ]]; then
    echo "  ❌ android-sdk+emulator~kvm still passes /dev/kvm or keeps its startup hook"
    exit 1
fi

finally
