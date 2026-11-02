#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: each music tool emits its own setup
for tool in lilypond csound chuck supercollider; do
    run rm -Rf $prj
    mkdir -p $prj
    run booth config $prj --no-tui --select "$tool"
    assert-line "$prj/.booth/Boothfile" "setup $tool" ''  "$tool: Boothfile runs its setup"
done

# Test 2: lilypond+play adds FluidSynth
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lilypond+play"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup lilypond' ''    "lilypond+play: LilyPond setup"
assert-line "$boothfile" 'setup fluidsynth' ''  "lilypond+play: FluidSynth setup"

# Test 3: host-audio+jack adds the JACK route and the PipeWire socket, read-only
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "supercollider/host-audio+jack"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" 'setup host-audio --jack' ''  "+jack: JACK route setup"
assert-line "$config" '    "-v", "$XDG_RUNTIME_DIR/pipewire-0:' '/run/pipewire/pipewire-0:ro",'  "+jack: PipeWire socket mounted read-only"
assert-line "$config" '    "-e", "PIPEWIRE_RUNTIME_DIR=' '/run/pipewire"'  "+jack: PIPEWIRE_RUNTIME_DIR set"
assert-line "$config" '    "-e", "PULSE_SERVER=' 'unix:/run/pulse/native",'  "+jack: the PulseAudio route stays"

finally
