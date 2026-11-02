#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: host-audio alone — setup line, read-only socket mount, PULSE_SERVER
run booth config $prj --no-tui --select "host-audio"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" 'setup host-audio' ''  "Boothfile runs the host-audio setup"
assert-line "$config" '    "-v", "$XDG_RUNTIME_DIR/pulse/native:' '/run/pulse/native:ro",'  "socket is mounted read-only"
assert-line "$config" '    "-e", "PULSE_SERVER=' 'unix:/run/pulse/native"'  "PULSE_SERVER points at the socket"

# Test 2: alongside a language — its run-args survive and the setup still lands
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "python/host-audio"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" 'setup host-audio' ''  "python/host-audio: host-audio setup present"
assert-line "$config" '    "-e", "PYTHONDONTWRITEBYTECODE=' '1",'  "python/host-audio: python run-args kept"
assert-line "$config" '    "-e", "PULSE_SERVER=' 'unix:/run/pulse/native"'  "python/host-audio: PULSE_SERVER set"

finally
