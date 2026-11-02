# Sound from a booth (`host-audio`, `browser-audio`)

Code in a booth can play sound two ways. Pick one:

| Template | Sound plays | Works on |
|----------|-------------|----------|
| `host-audio` | through **your computer's speakers**, at native latency, via the host's sound server | Linux hosts with local Docker |
| `browser-audio` | in **the browser tab viewing the booth** — click *Sound on* in the Booth panel | any host: Linux, macOS, Windows, a remote Docker host |

```bash
booth config --select 'python/host-audio'      # or add host-audio to any selection
./booth -- paplay sound.wav
```

Two examples use it:

- **[drum-beat-example](../examples/workspaces/drum-beat-example/)** — a drum beat synthesized in plain
  Python and played with `just beat`.
- **[music-example](../examples/workspaces/music-example/)** — one progression across four music
  tools (below), played together with `just jam`.

---

## Music tools

Each is its own template; select it with `host-audio` or `browser-audio` to hear it. All of them also render to a file
with no audio device, so they are useful on any host.

| Template | What you write | Plays through | Renders with |
|----------|----------------|---------------|--------------|
| `lilypond` (+`play`) | Sheet music as text (`.ly`) → PDF score + MIDI; `+play` adds FluidSynth and a General MIDI SoundFont to hear the MIDI | FluidSynth → PulseAudio | `fluidsynth -F out.wav` |
| `csound` | Instruments and a score (`.csd`) | ALSA → PulseAudio (`-odac`) | `csound -o out.wav` |
| `chuck` | Strongly-timed code — drum patterns read like the beat (`.ck`) | ALSA → PulseAudio | `chuck --silent` + `WvOut` |
| `supercollider` | Synthesis and live coding (`.scd`) | **JACK → PipeWire — needs `host-audio+jack`** | `Score.recordNRT` |

```bash
booth config --select 'lilypond+play/csound/chuck/supercollider/host-audio+jack'
```

---

## In the browser: `browser-audio`

```bash
booth config --select 'python/browser-audio'
```

Open the booth in the browser and click **Sound on** in the Booth panel; from then on, sound made in
the booth plays in that tab. The choice is remembered by the browser: after a reload, the first
click or key press anywhere on the page turns it back on (browsers allow sound only after one).

| Piece | What it does |
|-------|--------------|
| `setup browser-audio` | Installs `pulseaudio` and starts it as the booth user at each start, with one output: a silent virtual sink, `booth`, listening at `/run/booth-audio/native`. |
| `-e PULSE_SERVER=unix:/run/booth-audio/native` | Points every PulseAudio client in the booth — and ALSA, through its pulse plugin — at that server. |
| `GET /booth-messages/api/audio/stream` | Records the sink's monitor with `parec` and sends it as raw 16-bit 48 kHz stereo, for as long as the page listens. Behind the booth's login, like the rest of the Booth panel's API. |
| The Booth panel's **Sound** button | Reads the stream and plays it with WebAudio, about 0.1 s behind the booth. Shows only in a booth with `browser-audio`. |

Everything that works with `host-audio` works the same here — `paplay`, `aplay`, FluidSynth,
Csound, ChucK — except JACK: there is no `+jack` for the browser yet, so SuperCollider's live server
has no output (it still renders to a file). It needs no host mount, so it asks no consent and gives
the booth no access to your microphone.

**Things to know:**

- **About 1.5 Mbit/s** per tab while Sound is on, silence included: the stream is uncompressed.
  Fine on a LAN and most connections; Sound off stops it.
- **Every tab with Sound on plays it**, each with its own stream. Anyone who can open the booth
  can listen — the same people who can already use its terminal.
- **Only browser pages get it.** `./booth -- paplay x.wav` from the host plays into the booth's
  silent sink; open the booth in a browser with Sound on to hear it.

---

## How it works

A booth runs no sound server of its own. It borrows the host's:

| Piece | What it does |
|-------|--------------|
| `-v $XDG_RUNTIME_DIR/pulse/native:/run/pulse/native:ro` | Mounts the host's PulseAudio socket. PipeWire, the default on current Linux desktops, serves the same socket through `pipewire-pulse`. |
| `-e PULSE_SERVER=unix:/run/pulse/native` | Points every PulseAudio client in the booth at that socket. |
| `setup host-audio` | Installs `pulseaudio-utils` (`paplay`, `pactl`, `parec`), `alsa-utils` (`aplay`), and ALSA's pulse plugin, made ALSA's default device in `/etc/asound.conf`. |

So both kinds of program reach the host:

- **PulseAudio clients** — `paplay`, browsers, most synths and players — through `PULSE_SERVER`.
- **ALSA-only programs** — `aplay`, and anything that opens ALSA's `default` device — through the pulse
  plugin, which also follows `PULSE_SERVER`.

Sound plays at native latency, on whatever output the host has chosen as its default.

### JACK programs: `host-audio+jack`

Some programs speak only JACK — SuperCollider's `scsynth` is the one in this catalog. Without a JACK
server it tries to start `jackd` and fails. The `+jack` extension reaches the host's PipeWire instead:

| Piece | What it does |
|-------|--------------|
| `-v $XDG_RUNTIME_DIR/pipewire-0:/run/pipewire/pipewire-0:ro` | Mounts PipeWire's native socket. |
| `-e PIPEWIRE_RUNTIME_DIR=/run/pipewire` | Tells PipeWire clients where it is. |
| `setup host-audio --jack` | Installs `pipewire-jack` and lists its `libjack` in `/etc/ld.so.conf.d/`, so every JACK program uses PipeWire's — no `pw-jack` prefix and no `jackd`. |

It needs a **PipeWire** host. On a plain-PulseAudio host there is no `pipewire-0`; the mount is skipped
and JACK programs fail to connect, while the PulseAudio route keeps working.

The mount is **read-only**. Connecting to a socket does not need a writable mount, and a read-only one
does not trigger booth's writable-host-mount consent prompt (see [Security](BOOTH_SECURITY.md#3-convenience-mounts-your-secrets-inside-the-booth)).

---

## Where `host-audio` works

| Host | Status |
|------|--------|
| **Linux, local Docker, PipeWire** | ✅ Works. Tested on PipeWire 1.6.2: PulseAudio, ALSA and JACK (`+jack`) playback, no cookie needed. |
| **Linux, local Docker, PulseAudio** | Expected to work (same socket path), not tested. If the server refuses the connection, it may want its cookie; mount `~/.config/pulse/cookie` too. No JACK route: `+jack` needs PipeWire. |
| **Linux, remote Docker host** (`DOCKER_HOST=ssh://…`) | ❌ The socket is on *that* machine, so the sound plays there, or nowhere — use `browser-audio`. |
| **macOS** (Docker Desktop, Podman machine) | ❌ Not supported — use `browser-audio`. Containers run in a Linux VM with no sound device, and macOS has no PulseAudio socket to mount. |
| **Windows** (Docker Desktop) | ❌ Not supported — use `browser-audio`. WSLg runs a PulseAudio server inside WSL, but a Docker Desktop container reaching it is untested. |
| **Rootless Podman** | Untested. |

**On an unsupported host, the booth still starts — it just has no sound.** `$XDG_RUNTIME_DIR` is unset
or has no `pulse/native`, so booth skips the mount and says so:

```text
   Skipping volume mount: host path does not exist: /pulse/native
```

Playing then fails with a clear error rather than hanging:

```text
$ paplay beat.wav
Connection failure: Connection refused
$ aplay beat.wav
aplay: main:850: audio open error: Connection refused
```

You can still *generate* sound in such a booth — render to a WAV file and play it on the host — or select `browser-audio` instead and hear it in the browser.

**Not built yet** (an idea, not a promise): on macOS, a PulseAudio server on the Mac reached over TCP
(`PULSE_SERVER=tcp:host.docker.internal:4713`), for native latency there too.

---

## Microphone access

The socket gives the booth the **whole** sound server, not just playback: code in the booth can also
**record from your microphone** (`parec`, `arecord`) and change volumes. Read-only mounting does not
limit this — it only stops the socket file itself from being replaced. Select `host-audio` only for a
booth whose code you trust, as with any convenience mount.

`+jack` mounts PipeWire's own socket, which reaches further: PipeWire also carries **cameras** it
manages and screen-share streams the desktop offers through it. Add `+jack` only when a JACK program
needs it.

---

## Troubleshooting

```bash
pactl info | grep -E '^(Server Name|Default Sink):'   # which server and output the booth sees
pactl list sinks short                                 # every output the host has
```

- **No `Server Name`** — the socket is not mounted. Check the start-up output for *Skipping volume
  mount*, and that `ls -l $XDG_RUNTIME_DIR/pulse/native` shows a socket on the host.
- **It plays, but not where you are listening** — the sound goes to the host's *default* output. Change
  it on the host, or pick one for a single command: `paplay --device=<sink-name> beat.wav`.
- **An ALSA program is silent** — it may open a hardware device (`hw:0`) instead of `default`; point it
  at `default` (or `pulse`).
