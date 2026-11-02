#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin
status="$prj/.status"

# Test 1: browser-audio alone — the client setup, then the in-booth server, and
# PULSE_SERVER at that server; no host socket is mounted.
run booth config $prj --no-tui --select "browser-audio"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" 'setup host-audio' ''     "Boothfile runs the PulseAudio client setup"
assert-line "$boothfile" 'setup browser-audio' ''  "Boothfile runs the browser-audio setup"
assert-line "$config" 'run-args = ' '["-e", "PULSE_SERVER=unix:/run/booth-audio/native"]'  "PULSE_SERVER points at the booth's own server"
echo "host mounts: $(grep -c 'XDG_RUNTIME_DIR' "$config")" > "$status"
assert-line "$status" 'host mounts: ' '0'           "no host sound socket is mounted"

# Test 2: alongside a language — its run-args survive and both setups still land
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "python/browser-audio"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" 'setup browser-audio' ''  "python/browser-audio: browser-audio setup present"
assert-line "$config" '    "-e", "PYTHONDONTWRITEBYTECODE=' '1",'  "python/browser-audio: python run-args kept"
assert-line "$config" '    "-e", "PULSE_SERVER=' 'unix:/run/booth-audio/native"'  "python/browser-audio: PULSE_SERVER set"

finally
