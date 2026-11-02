# Music Example

Four music-as-code tools, one song. Each tool plays one part of the same four bars — Am, F, C, G at
120 BPM — and `just jam` plays them together on **your** speakers:

| Part   | Tool | File | Plays through |
|--------|------|------|---------------|
| Melody | **LilyPond** engraves the score (PDF + MIDI), **FluidSynth** plays the MIDI | `score/melody.ly` | PulseAudio |
| Drums  | **ChucK** — kick, snare and hi-hat made from oscillators and noise | `drums/drums.ck` | ALSA → PulseAudio |
| Bass   | **Csound** — a sawtooth through a closing Moog-style filter | `bass/bass.csd` | ALSA → PulseAudio |
| Pad    | **SuperCollider** — detuned saws, one chord per bar | `pad/pad.scd` | JACK → PipeWire |

**Needs a Linux host with PipeWire and local Docker** to hear it (the `host-audio` template and its
`+jack` extension). On macOS and Windows the booth still starts and `just render` / `just score` work —
you get the WAV files and the PDF, just no live sound. See
[Sound from a booth](../../../docs/BOOTH_AUDIO.md).

## Quick start

```bash
cd examples/workspaces/music-example
just jam                  # render all four parts, then play them together
```

One part at a time, live:

```bash
just drums                # ChucK
just bass                 # Csound
just melody               # LilyPond -> MIDI -> FluidSynth
just pad                  # SuperCollider
```

And without sound:

```bash
just score                # out/melody.pdf and out/melody.midi — open the PDF to see the sheet music
just render               # out/{melody,drums,bass,pad}.wav
just --list
```

## Change the music

- **Drums** — edit the step patterns at the top of `drums/drums.ck` (`x` hit, `o` accent, `.` rest).
- **Melody** — edit the notes in `score/melody.ly`; `just score` re-engraves the PDF too.
- **Bass** — `iSteps[]` in `bass/bass.csd` is the octave/fifth pattern over each chord root.
- **Pad** — `chords` in `pad/pad.scd`, as MIDI note numbers.

Keep the four in step: each part is 4 bars at 120 BPM.

## Why `just jam` renders first

Live, SuperCollider spends about a second booting its server before the pad can sound, so four live
players started together would not line up. `jam.sh` renders every part to WAV (offline, and fast),
then starts four `paplay`s at once.

## What's included

| Component | Details |
|-----------|---------|
| Templates | `lilypond+play`, `csound`, `chuck`, `supercollider`, `host-audio+jack` |
| Scripts   | `render.sh` (every part to `out/*.wav`), `jam.sh` (render, then play together) |
