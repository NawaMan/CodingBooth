# booth idle

> Shut down booths that nobody is using — with a "still there?" prompt first, so you don't lose an active session by surprise.

`--idle-time` arms an in-container watchdog. After `s` seconds with no user input, the booth prompts the user through the message overlay; if they don't respond within `t` seconds, the booth shuts itself down. The host CLI exits with `--idle-exit-code` so schedulers and wrappers can distinguish idle shutdown from a user-initiated stop.

```bash
# Prompt after 5 min idle; shut down 60 s later if no response; exit 0 on idle shutdown.
codingbooth --variant codeserver --idle-time 300

# Custom grace period (30 s) and a sentinel exit code for cron.
codingbooth --variant codeserver --idle-time 600,30 --idle-exit-code 7
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Flags and Config Keys](#flags-and-config-keys)
- [How It Works](#how-it-works)
- [Activity Detection](#activity-detection)
- [Pause and Disable](#pause-and-disable)
- [Per-Variant Behavior](#per-variant-behavior)
- [Exit Code Propagation](#exit-code-propagation)
- [Limitations](#limitations)

---

## Overview

Idle shutdown exists for two scenarios:

- **Shared hosts** — a teammate or CI runner forgot to stop their booth; the host is paying for an idle container.
- **Pay-per-minute compute** — a cloud shell or sandbox where wall-clock time costs money.

The design has three explicit stages so it never kills a session someone is still in:

1. **Idle timer** — `IDLE_TIME` seconds with no activity from the user.
2. **Grace prompt** — a modal on the web overlay asking the user to confirm they're still there.
3. **Shutdown** — if no response within `SHUTDOWN_TIME` seconds, `booth--shutdown --yes` runs and the container exits.

The prompt is important: a 15-minute compile is "idle" from the input side but absolutely not a good moment to shut down.

---

## Flags and Config Keys

| CLI flag             | Config (`config.toml`) | Env var                    | Default | Description                                         |
|----------------------|------------------------|----------------------------|---------|-----------------------------------------------------|
| `--idle-time s[,t]`  | `idle-time = s`        | `CB_IDLE_TIME`             | `0`     | Idle threshold in seconds (0 disables).             |
|                      | `idle-shutdown-time=t` | `CB_IDLE_SHUTDOWN_TIME`    | `60`    | Grace seconds after the prompt before shutdown.     |
| `--idle-exit-code n` | `idle-exit-code = n`   | `CB_IDLE_EXIT_CODE`        | `0`     | Host CLI exit code when the booth shuts down idle.  |

`--idle-time` rejects non-positive integers:

```
--idle-time requires a positive integer, got "-5"
--idle-time shutdown time requires a positive integer, got "0"
```

When `IdleTime > 0`, the CLI injects three `-e BOOTH_IDLE_*` env vars into `docker run`. When it's `0`, no env vars are set and the in-container monitor exits immediately — zero cost.

---

## How It Works

```
host CLI                           container
────────                           ─────────
--idle-time 300,60                 booth--idle-monitor (bg)
  │                                  │
  │  -e BOOTH_IDLE_TIME=300            loop:
  │  -e BOOTH_IDLE_SHUTDOWN_TIME=60      if .idle-disabled or .idle-pause-until → hold
  │  -e BOOTH_IDLE_EXIT_CODE=0           else sleep 300 (in 10s chunks, re-checks hold)
  │                                      if .last-activity > sleep_start  → restart loop
  │                                      write .booth/.tmp/messages/idle-XXX.msg.json
  │                                        (idle-prompt: I'm here / Pause N min / Disable)
  │                                      poll for .response.json (up to 60 s)
  │                                      if "pause:N"  → write .idle-pause-until → restart
  │                                      if "disable"  → touch .idle-disabled   → restart
  │                                      if "ok" / any other response → restart loop
  │                                      else → booth--shutdown --yes
  │                                             touch .booth/.tmp/.idle-shutdown
  ▼                                ────────────────────────────────────────
container exits
  │
  ▼
checkAndCleanIdleShutdownMarker()  — sees .idle-shutdown marker
  → returns IdleShutdownError{ExitCode: N}
  → host CLI exits N
```

Key paths:

- Watchdog script: `variants/base/setups/booth--idle-monitor`
- Activity timestamp: `.booth/.tmp/.last-activity` (Unix seconds, written by the message API)
- Prompt channel: `.booth/.tmp/messages/idle-*.msg.json` (same queue as `booth message send`)
- Pause / Disable state: `.booth/.tmp/.idle-pause-until`, `.booth/.tmp/.idle-disabled`
- Shutdown marker: `.booth/.tmp/.idle-shutdown`
- Host-side detection: `IdleShutdownError` raised from `cli/src/pkg/booth/booth.go`

---

## Activity Detection

"Activity" is **user input into the web overlay**, not container CPU or disk.

- The overlay (`booth-message-overlay.html`) listens for `keydown`, `mousemove`, `mousedown`, `wheel`, and `touchstart` events.
- These are throttled to one report per 60 seconds to keep the API quiet.
- Each report `POST`s to `/booth-messages/api/activity`, which writes the current Unix timestamp to `.booth/.tmp/.last-activity`.
- The monitor checks `.last-activity > sleep_start` at the end of each idle window.

Consequences worth knowing:

- A long compile, a streaming log tail, or a network sync inside the booth is **not** activity. That's by design — a crashed IDE that's still compiling shouldn't keep a forgotten booth alive.
- Closing the browser tab freezes activity reporting. The next cycle will trigger the prompt — which nobody will see — and then the shutdown grace period will elapse. That's also correct.
- Activity is **per-booth**, not per-user. Any browser connected to the overlay counts.

---

## Pause and Disable

Two orthogonal ways to tell the watchdog to stand down:

- **Pause** — time-boxed hold (`N` minutes). Auto-resumes to normal cadence when the window elapses.
- **Disable** — indefinite hold. Only cleared by an explicit Resume or container restart.

When `--idle-time` is armed, the web overlay's lifecycle panel shows a status chip that reflects state:

- `⏱ Idle: 15m` (green) — normal cadence, no hold in effect.
- `⏱ Idle: PAUSE 1h 42m` (blue) — time-boxed Pause; the chip counts the remaining duration down and reverts to the green "normal" state automatically when it hits zero.
- `⏱ Idle: DISABLED` (red, pulsing) — monitoring is off until the user resumes or the booth restarts.

Clicking the chip opens a sectioned "Idle shutdown" control dialog:

1. **Header + description** — "This booth shuts down after **`<idle-time>`** of keyboard or mouse inactivity, so an idle run doesn't rack up unexpected costs." When state is already paused or disabled, the description reflects the current state instead.
2. **"Hold off for a while"** — a one-time time-boxed Pause. Minute input defaulted to 60 (1h), capped at 7 days. Copy: "Running a long build, or stepping away for coffee? Pause this for a while."
3. **"Turn it off entirely"** (shown when state is normal) — red-styled section with a `[ Disable idle shutdown ]` button. Copy: "Cost isn't a concern for this booth. You'll lose the safety net against runaway charges." When state is already paused or disabled, this section is replaced by **"Back to normal"** with a `[ Resume normal idle ]` button.
4. **"Got it, carry on"** — `[ Close ]` button. Copy: "Close this and let the `<idle-time>` timer keep watching."

The "I'm here" acknowledge from the idle prompt is intentionally absent here: opening the dialog is itself the acknowledgement.

The "Still using this booth?" grace-window prompt reuses the same sectioned layout as the chip dialog, so the controls feel familiar whether the user proactively opened it or it fired on timeout. The header shows a **live countdown** — the "shut down in **N seconds**" label ticks every second, driven by the message's `expires` timestamp. Sections:

1. **Hold off for a while** — time-boxed Pause (same control as the chip dialog).
2. **Turn it off entirely** — danger-styled Disable.
3. **I'm still here** — `[ I'm here ]` button that resets the timer and keeps watching. Takes the place of the chip dialog's "Got it, carry on" section.

### State files (`.booth/.tmp/`)

- `.idle-disabled` — zero-byte flag. Presence ⇒ disabled.
- `.idle-pause-until` — single-line file with the epoch second when the time-boxed Pause ends.
- `.idle-base-override` — single-line integer (seconds) overriding `BOOTH_IDLE_TIME` for this session.

Both are ephemeral. `.booth/.tmp/` is cleared on container start and exit (same treatment as `.shutdown-requested` / `.idle-shutdown`), so **a restart always returns the booth to normal idle cadence** — by design, so a forgotten Disable can't outlive a reboot.

### API

The chip and dialog are a thin client over four endpoints on the in-container message-API server (proxied through nginx at `/booth-messages/api/idle/`):

| Method | Path              | Body                  | Effect                                                                          |
|--------|-------------------|-----------------------|---------------------------------------------------------------------------------|
| GET    | `/idle/state`     | —                     | Returns `{enabled, idle_time, base_idle_time, shutdown_time, disabled, pause_until}` — `idle_time` is the effective value (override if set, else base). |
| POST   | `/idle/pause`     | `{"seconds": N}`      | Writes `now + N` to `.idle-pause-until`. Clears any Disable. Capped 7d.         |
| POST   | `/idle/disable`   | —                     | Touches `.idle-disabled`. Clears any active Pause.                              |
| POST   | `/idle/resume`    | —                     | Removes both marker files.                                                      |
| POST   | `/idle/set-time`  | `{"seconds": N}`      | Writes N to `.idle-base-override` — overrides the base idle time for this session. Cleared on restart. Monitor picks up within ~10 s. |

The same endpoints are available to scripts inside the container, so a long-running test can `curl -X POST -d '{"seconds":7200}' localhost:10007/booth-messages/api/idle/pause` to keep the booth alive programmatically.

---

## Per-Variant Behavior

| Variant          | Prompt surface              | Behavior on idle                                                  |
|------------------|-----------------------------|-------------------------------------------------------------------|
| `codeserver`     | Message overlay (modal)     | Prompts first, shuts down after grace if no response.             |
| `notebook`       | Message overlay (modal)     | Same as codeserver.                                                |
| `xfce` / `kde`   | Message overlay (modal)     | Same as codeserver. Activity events come from the noVNC canvas.   |
| `base` / console | No web overlay              | Monitor runs, but `.last-activity` is never updated → shuts down directly after `IDLE_TIME` with no prompt. |

The terminal case is intentional: a headless booth has no UI to prompt against, and if you set `--idle-time` on it, you're saying "if nothing touches this for N seconds, kill it."

---

## Exit Code Propagation

`--idle-exit-code` is what the **host CLI** exits with — not the container's exit status. The flow:

1. Monitor writes `.booth/.tmp/.idle-shutdown` before calling `booth--shutdown --yes`.
2. Container exits cleanly.
3. After the container exits, the host CLI inspects `.booth/.tmp/.idle-shutdown`. If present, it cleans the marker and returns an `IdleShutdownError` carrying the configured exit code.
4. `cli/src/cmd/codingbooth/run.go` translates that error into `os.Exit(code)`.

This lets an outer orchestrator distinguish "user ran `booth stop`" (exit 0) from "booth auto-shut-down for being idle" (exit whatever you configured), e.g.:

```bash
codingbooth --variant codeserver --idle-time 300 --idle-exit-code 7
case $? in
  0) echo "user-initiated stop" ;;
  7) echo "auto-shutdown (idle)"; log-to-metrics ;;
  *) echo "crash or other error"; exit 1 ;;
esac
```

---

## Limitations

- **Browser tab closed = no prompt visible.** The booth will still shut down cleanly, but the user never sees the "still there?" modal. Setting a generous `IDLE_TIME` is more forgiving than shrinking the grace period. Pause or Disable set before the tab closes still hold, since the state lives in files on disk — but you can't open the control dialog or see the chip until you reload.
- **No activity signal from terminal-only variants.** On `base`, idle is purely wall-clock and there is no overlay chip; Pause/Disable are overlay-only features.
- **Per-booth, not per-session.** If two people share a booth, either one's mouse movement resets the timer, and either one can pause or disable it.
- **Disable has no auto-expiry.** It holds until the user explicitly resumes or the booth restarts. The overlay flags this with a red pulsing `Idle: DISABLED` chip and a warning in the dialog; prefer Pause when you know how long you need.
- **Pause/Disable check cadence is ~10 s.** The monitor samples state in 10-second chunks, so a just-set hold takes up to 10 s to take effect rather than being instant.
- **No dedicated integration test yet.** Happy-path env-var wiring and error messages are covered by `tests/dryrun/test021--idle-time.sh` and `test022--idle-pause-extend.sh` covers static wiring for Pause/Disable. Full idle→prompt→shutdown and Pause/Disable flows are exercised manually.
