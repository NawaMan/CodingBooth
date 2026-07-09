# desktop-gnome (real GNOME Shell on Wayland) — investigation & restart notes

> **Status: PARKED (2026-07-08).** Real Ubuntu GNOME Shell, streamed to the browser, does
> **not** work in a normal (non-systemd) booth container. Root cause is session
> infrastructure (logind), **not** the streaming transport. A working Wayland desktop
> shipped instead as **`desktop-wayland`** (labwc + wayvnc + noVNC) — see
> [BOOTH_VARIANTS.md](../BOOTH_VARIANTS.md). This document records what was tried, the exact
> wall, the component versions, and how to restart the attempt.
>
> **Parked code:** git branch `wip/desktop-gnome-webrtc` (the WebRTC pipeline). The RDP
> go/no-go was run in throwaway debug containers (not committed).

Back to [README](../../README.md)

---

## Goal

Deliver the *genuine* Ubuntu **GNOME Shell** desktop (Mutter/Wayland) into a browser tab,
over the single booth TCP port, from a **headless container** (no GPU, no display manager).

Why it's hard: `wayvnc` (used by `desktop-wayland`) only captures **wlroots** compositors.
GNOME uses **Mutter**, which is not wlroots — so GNOME needs its own remote-desktop stack.

---

## TL;DR verdict

Two transports were attempted (WebRTC, then RDP+Guacamole). **Both fail on the same
transport-independent wall:**

> GNOME's stack — `gnome-shell` → `org.gnome.Mutter.RemoteDesktop`/`ScreenCast` → **logind
> (`org.freedesktop.login1`)** — requires **systemd running as PID 1**. A normal booth
> container runs a single process, not an init system, so `systemd-logind` is absent.
> Started standalone, `systemd-logind` is flaky (comes up, creates `seat0`, then dies), so
> `gnome-shell` crashes during init (`LoginManagerSystemd` exception) and never registers the
> Mutter D-Bus interfaces that the remote-desktop daemon needs.

**To restart successfully, the `desktop-gnome` container must run under systemd as PID 1.**
That is the prerequisite; everything else (grd, gateway) is downstream of it.

---

## Approaches attempted

### Attempt 1 — WebRTC (custom GStreamer pipeline)

Mutter `ScreenCast` (PipeWire) → `pipewiresrc` → `vp8enc` → `webrtcbin` → browser; input via
`org.gnome.Mutter.RemoteDesktop`; signaling over libsoup3 websocket. Code on branch
`wip/desktop-gnome-webrtc`.

Proven along the way, then blocked:
- ✅ headless `gnome-shell --wayland --headless --virtual-monitor` renders (captured a real
  frame with the branded wallpaper) — **but only when logind was (temporarily) alive**.
- ✅ `set_state` deadlock fixed (pipewiresrc+webrtcbin can't be driven single-process from an
  event-loop callback → run capture as a separate `gst-launch` process feeding `udpsrc`).
- ❌ **Blocker:** on a *static, freshly-started* desktop, Mutter's headless ScreenCast emits
  **zero frames** (`gst-launch pipewiresrc path=<node> num-buffers=1 ! fakesink` → hangs/124).
  It only emits on screen damage, and headless has no initial paint. Pointer/Super nudges via
  RemoteDesktop did not reliably force a frame. This is exactly what `gnome-remote-desktop`'s
  sanctioned headless mode handles for you — which motivated Attempt 2.

### Attempt 2 — RDP via `gnome-remote-desktop` + a FreeRDP-3 web gateway (Path A)

The sanctioned GNOME remote path. Go/no-go run in a debug container with
`--device /dev/fuse --cap-add SYS_ADMIN`, using `xfreerdp3` rendering into `Xvfb` to capture
what grd sends. How far it got, **in order**:

1. ✅ grd RDP **authentication works** (NLA; reached RDP licensing). Needs `gnome-keyring`
   with a **seeded default "login" keyring** or `grdctl set-credentials` stores nowhere and
   grd logs *"Credentials are not set, denying client."*
2. ⚠️ grd **crashes without `/dev/fuse`**: `[FUSE Clipboard] Failed to mount FUSE filesystem`
   is a **fatal** GLib `ERROR` (aborts the daemon right after auth). There is **no** grdctl /
   gsetting to disable the clipboard. → **Path A requires `--device /dev/fuse --cap-add
   SYS_ADMIN`.**
3. ✅ With fuse present, `xfreerdp3` reached the **`rdpgfx` graphics channel** (framebuffer
   formats negotiated) — frames were one step away.
4. ❌ **Blocker:** grd → *"Failed to start remote desktop session:
   `org.gnome.Mutter.RemoteDesktop was not provided by any .service files`"* — because
   `gnome-shell` had crashed on `LoginManagerSystemd` (logind down). Same wall as Attempt 1.

**Note on the FreeRDP version issue** (the usually-cited Guacamole blocker): it is real but
*downstream*. Ubuntu 24.04 ships `guacd`/`libguac-client-rdp` **1.3.0 linked to FreeRDP 2**,
while grd is **FreeRDP 3.5**; their RDP security negotiation is incompatible (every mode
refused). Fixing it needs `guacamole-server ≥ 1.6` (FreeRDP 3) — but that only matters *after*
the logind/session wall is solved, since grd can't produce a session at all yet.

---

## What actually works (proven, reusable)

- headless `gnome-shell` **renders** and Mutter `ScreenCast`/`RemoteDesktop` **do work** —
  **when logind is alive**. The whole problem is keeping logind alive.
- grd RDP **auth + graphics channel** are reachable in a container (with `/dev/fuse`).
- `gnome-keyring` default-collection seeding for grd credentials.
- The **delivery** layer is a solved problem: the shipping `desktop-wayland` variant proves
  websockify + noVNC over the single port; a FreeRDP-3 HTML5 client would slot in equivalently
  for RDP.

---

## Component versions (Ubuntu 24.04.4 LTS "Noble", as of 2026-07-08)

| Component | Version | Notes |
|---|---|---|
| Ubuntu (base image) | 24.04.4 LTS | `ARG UBUNTU_VERSION=24.04` |
| GNOME Shell | 46.0 | |
| Mutter | 46.2 | provides `org.gnome.Mutter.{ScreenCast,RemoteDesktop}` |
| gnome-remote-desktop | 46.3-0ubuntu1.2 | RDP; needs `/dev/fuse` for clipboard |
| gnome-keyring | 46.1-2ubuntu0.2 | grd credential store |
| systemd / systemd-logind | 255.4-1ubuntu8.16 | **the blocker** — needs PID 1 |
| PipeWire | 1.0.x (Ubuntu 24.04) | ScreenCast transport |
| WirePlumber | 0.4.17-1ubuntu4.1 | |
| FreeRDP (client `xfreerdp3`, `libfreerdp3-3`) | 3.5.1+dfsg1-0ubuntu1.6 | grd's RDP is FreeRDP 3 |
| guacd / libguac-client-rdp | 1.3.0-1.3ubuntu1 | **links FreeRDP 2** → incompatible with grd |
| gstreamer1.0-plugins-bad (webrtcbin) | 1.24.2-1ubuntu4 | Attempt 1 |
| libnice10 | 0.1.21-2build3 | Attempt 1 (WebRTC ICE) |
| python3-gi | 3.48.2-1 | Attempt 1 |
| gir1.2-soup-3.0 | 3.4.4-5ubuntu0.7 | Attempt 1 (signaling) |
| labwc / wayvnc (shipped `desktop-wayland`) | 0.7.1 / 0.7.2 | the working alternative, for reference |

---

## Recommended restart plan (gated)

Do **not** start by building the Guacamole/FreeRDP-3 gateway. Solve the prerequisite first,
gate by gate:

1. **Gate 1 — systemd-init GNOME container.** Build a `desktop-gnome` image that runs
   **systemd as PID 1** (`/sbin/init`), with the cgroup mount, `--cap-add SYS_ADMIN`, and
   `--device /dev/fuse`. Prove `logind` is healthy (`loginctl` works; `login1` answers) and
   `gnome-shell` starts without the `LoginManagerSystemd` crash. This is an architectural
   departure from how booths run today (one process) and needs a decision.
2. **Gate 2 — grd headless emits frames.** With a healthy session, use grd's *sanctioned
   headless ("Remote Login")* mode and confirm a real GNOME frame arrives over RDP
   (`xfreerdp3` → `Xvfb` → screenshot). This is the bit never reached; it's the real risk once
   logind is solved.
3. **Gate 3 — browser gateway.** Build/obtain a **FreeRDP-3** HTML5 gateway
   (`guacamole-server ≥ 1.6`, or `guacamole-lite` + a FreeRDP-3 `guacd`) and put it behind the
   booth overlay (`IFRAME_SRC` → the gateway's client page), reusing the nginx wrapper.

If Gate 1 or 2 is judged not worth the cost, `desktop-wayland` (labwc) is the shipping Wayland
desktop, and a GNOME-*flavored* labwc (GNOME apps + Adwaita theme) is the cheap middle ground.

---

## How to reproduce the go/no-go

The RDP go/no-go recipe is saved in the repo at
[`experiments/desktop-gnome/`](../../experiments/desktop-gnome/) — `grd-gonogo.sh` (headless
gnome-shell + grd bringup) and `rdp-capture.sh` (Xvfb + `xfreerdp3` + `import` capture), with
run instructions in that folder's README. Key facts:

- Bring up: system D-Bus + **standalone systemd-logind** (the fragile part) + PipeWire +
  `gnome-shell --wayland --headless --virtual-monitor 1280x800` + gnome-keyring (seeded
  default keyring) + `grdctl rdp set-tls-cert/key/credentials/enable` +
  `/usr/libexec/gnome-remote-desktop-daemon`.
- Container flags required: `--device /dev/fuse --cap-add SYS_ADMIN`.
- Capture: `Xvfb :99 -screen 0 1280x800x24` + `DISPLAY=:99 xfreerdp3 /v:127.0.0.1:3389
  /u:coder /p:… /cert:ignore /gdi:sw` + `DISPLAY=:99 import -window root frame.png`.
- Expected current failure: grd logs *"org.gnome.Mutter.RemoteDesktop was not provided"* and
  `gnome-shell` log shows the `LoginManagerSystemd` exception → confirms the logind wall.
