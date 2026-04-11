# booth runtime

> Display session timers — track elapsed time and countdown to shutdown.

`--show-run-time` and `--show-count-down` add optional timer displays to the booth UI. Use them to show how long a session has been running, or count down to a scheduled end time.

```bash
# Show elapsed time from now
booth --show-run-time

# Show elapsed time from a specific start (e.g. billing start)
booth --show-run-time $(date +%s)

# Count down to a shutdown time (2 hours from now)
booth --show-count-down $(( $(date +%s) + 7200 ))

# Both together
booth --show-run-time $(date +%s) --show-count-down $(( $(date +%s) + 7200 ))
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Flags](#flags)
- [How It Works](#how-it-works)
- [Countdown Colors](#countdown-colors)
- [5-Minute Warning](#5-minute-warning)
- [Terminal Variant](#terminal-variant)
- [Configuration](#configuration)
- [Examples](#examples)

---

## Overview

Session timers help users track time — whether it's how long they've been working or how much time remains before the booth shuts down. This is useful for:

- **Classrooms and exams** — students see a countdown to submission deadline
- **Billed compute sessions** — show elapsed time since billing started
- **Time-boxed workshops** — visual reminder of remaining time
- **CI/CD jobs** — track execution duration

Both timers are independent. You can use either, both, or neither.

---

## Flags

| Flag | Value | Description |
|------|-------|-------------|
| `--show-run-time` | `<epoch-seconds>` (optional) | Show elapsed time counting up. If no value given, starts from container launch. |
| `--show-count-down` | `<epoch-seconds>` (required) | Show time remaining until the given Unix epoch. |
| `--count-down-exit-code` | `<exit-code>` (required) | Exit code when countdown expires and auto-shutdown triggers (default: 0). |

Both values are **Unix epoch seconds** — the absolute number of seconds since 1970-01-01 00:00:00 UTC. This makes them timezone-safe: the same epoch means the same instant regardless of the host or container timezone.

To get the current epoch:

```bash
date +%s
```

To get an epoch N seconds in the future:

```bash
$(( $(date +%s) + SECONDS ))
```

---

## How It Works

### Web UI variants (base, code-server, notebook, desktop)

Timers appear in the booth UI:

- **Base (web-ttyd)** — timers display in the toolbar, to the left of the Restart and Shut Down buttons
- **Code-server, notebook, desktop** — timers display in the Booth lifecycle panel (top-left floating panel), above the Restart and Shut Down buttons

The format is `HH:MM:SS` when >= 1 hour, otherwise `MM:SS`.

- **Run time** — grey text, counts up every second
- **Countdown** — color-coded text, counts down every second (see [Countdown Colors](#countdown-colors))

When the countdown reaches zero:
- The timer displays **TIME'S UP** in flashing red
- If the lifecycle panel was collapsed, it auto-expands

Hover over each timer for a tooltip explaining what it shows.

### Terminal variant

The terminal variant (`booth --variant terminal` or `booth -- bash`) has no web UI, so timers are delivered via the shell prompt:

- **Prompt display** — before each command prompt, the shell shows the current run time and/or countdown with color coding
- **Toast notifications** — a background process sends toast messages at key thresholds (30m, 15m, 10m, 5m, 1m remaining)

See [Terminal Variant](#terminal-variant) for details.

---

## Countdown Colors

The countdown timer changes color as the deadline approaches:

| Remaining Time | Color |
|----------------|-------|
| > 15 minutes | Dark green |
| 10 - 15 minutes | Yellow |
| 5 - 10 minutes | Orange |
| < 5 minutes | Red |
| Expired | Red, flashing |

---

## 5-Minute Warning

When the countdown reaches 5 minutes remaining, a dialog overlay appears in all web UI variants:

> **5 Minutes Remaining**
> This booth session will end in approximately 5 minutes. Please save your work.
> [OK]

The user must click OK to dismiss the dialog. This ensures they are aware of the approaching deadline even if they haven't been watching the timer.

In the terminal variant, the same warning is delivered as a toast notification via `booth--msg`.

---

## Terminal Variant

In the terminal variant, timers integrate with the shell prompt and the booth messaging system. The prompt timers only appear in the terminal variant — other variants show timers in the web UI instead.

**Prompt display** (shown before each command):

```
[booth] ⏱ 01:23:45 elapsed
[booth] ⏱ 00:14:30 remaining
```

- Run time is shown in dim/grey text
- The countdown line follows the same color scheme (dark green / yellow / orange / red)

**Toast notifications** are sent at countdown milestones (30m, 15m, 10m, 5m, 1m) via the booth messaging system. Users see them in the prompt notification or by running `booth--msg`:

```
[booth] 1 pending message(s) — run booth--msg to respond
```

---

## Configuration

These flags can also be set via environment variables or `.booth/config.toml`:

### Environment variables

```bash
export CB_SHOW_RUN_TIME=1718000000
export CB_SHOW_COUNT_DOWN=1718007200
booth
```

### config.toml

```toml
show-run-time = "1718000000"
show-count-down = "1718007200"
```

---

## Examples

### Classroom: 90-minute exam

```bash
booth --show-count-down $(( $(date +%s) + 5400 ))
```

### Workshop: show both elapsed and remaining

```bash
START=$(date +%s)
booth --show-run-time "$START" --show-count-down $(( START + 7200 ))
```

### Billed session: track from billing start, no deadline

```bash
booth --show-run-time "$BILLING_START_EPOCH"
```

### Quick test: 2-minute countdown

```bash
booth --show-count-down $(( $(date +%s) + 120 ))
```

---

## Notes

- **Restart behavior**: When using `--show-run-time` with an explicit epoch, the timer survives restarts (the epoch is absolute). When using `--show-run-time` without a value ("now"), the timer resets on restart — this is intentional, as it tracks container uptime.
- **Auto-shutdown on expiry**: When the countdown reaches zero, the booth automatically shuts down. Use `--count-down-exit-code` to control the exit code — for example, `--count-down-exit-code 1` to signal a timeout failure, or leave it at the default (0) for expected session completion.
- **Timezone safety**: Both flags use Unix epoch seconds, which are timezone-independent. The host and container can be in different timezones without affecting the timers.
