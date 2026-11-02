# Drum Beat Example

This example makes sound from code and plays it on **your** speakers. `beat.py` synthesizes a drum beat —
kick, snare and hi-hat, each built from a sine wave or noise, no samples and no audio libraries — writes
it to a WAV file, and `paplay` sends it through the host's sound server. The `host-audio` template is
what connects the two: it mounts the host's PulseAudio/PipeWire socket into the booth and routes ALSA
there too.

**Needs a Linux host with local Docker.** On macOS and Windows the booth starts and `just render` works,
but there is no sound to play through — see [Sound from a booth](../../../docs/BOOTH_AUDIO.md).

**Stack:** Python 3.14 (standard library only), `host-audio`

## Quick start

```bash
cd examples/workspaces/drum-beat-example
just beat                 # render 4 bars at 100 BPM and play them
just beat 128 8           # 8 bars at 128 BPM
```

Or from inside the booth (`booth`), the same recipes:

```bash
just --list
just sound-check          # which host sound server and output the booth sees
just render --bpm 90 --out slow.wav
just play slow.wav        # through PulseAudio
just play-alsa slow.wav   # through ALSA — same speakers
```

## Make your own groove

Edit `PATTERN` in `beat.py` — 16 steps per bar, `x` a hit, `o` an accent, `.` a rest:

```python
PATTERN = {
    "kick":  "x.....x...x.....",
    "snare": "....x.......x..o",
    "hat":   "x.x.x.x.x.x.x.xo",
}
```

The voices are short functions (`kick`, `snare`, `hat`) — change a decay or a pitch and hear the result
on the next `just beat`.

## What's included

| Component | Details |
|-----------|---------|
| Language  | Python (standard library only: `wave`, `math`, `random`) |
| Audio     | `host-audio` — host socket mount, `paplay`/`pactl`, `aplay` via ALSA's pulse plugin |
| Sample    | `beat.py` — synthesizer, sequencer and WAV writer in ~100 lines |
