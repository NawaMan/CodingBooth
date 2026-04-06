# booth message

> Send interactive messages and toast notifications to users inside a running booth.

`booth message` lets you communicate with users inside running booths — show dialogs that require a response, or fire-and-forget toast notifications that auto-dismiss.

```bash
# Ask a yes/no question (blocks until user responds)
booth message send --name my-booth --title "Deploy?" --body "Deploy to staging?" --type yes-no

# Show a toast notification (returns immediately)
booth message send --name my-booth --title "Build done" --body "Build completed successfully." --type toast
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Subcommands](#subcommands)
- [Message Types](#message-types)
- [Flags](#flags)
- [Toast Notifications](#toast-notifications)
- [How It Works](#how-it-works)
- [Examples](#examples)

---

## Overview

Booth messaging provides a way for scripts, CI pipelines, or the host CLI to present interactive UI to users working inside a booth. Messages appear as overlay dialogs on top of the booth's web UI (terminal, VS Code, Jupyter, or desktop).

All variants use the same rendering mechanism — an nginx wrapper that injects an HTML overlay into the page. This means messages look and behave identically across all variants.

---

## Subcommands

### `booth message send`

Send a message and (for interactive types) wait for a response.

```bash
booth message send [flags]
```

| Flag            | Description                                                        | Required |
|-----------------|--------------------------------------------------------------------|----------|
| `--title`       | Message title                                                      | Yes      |
| `--body`        | Message body text                                                  | Yes      |
| `--type`        | Message type (see [Message Types](#message-types))                 | No (default: `yes-no`) |
| `--name`        | Target booth name (default: current directory name)                | No       |
| `--options`     | Comma-separated options (for `choice`, `choice-text`, `radio`, `checkbox`) | Required for those types |
| `--expires`     | Timeout duration (e.g., `5m`, `1h`). Default: 10m for interactive, 30s for toast | No |

**Output:** Prints the message ID on the first line. For interactive types, prints the user's answer on the second line after they respond (or `timeout` if expired).

### `booth message list`

List all messages (pending and answered) for a booth.

```bash
booth message list [--name <booth>]
```

### `booth message response`

Read the response for a specific message.

```bash
booth message response [--name <booth>] <msg-id>
```

---

## Message Types

| Type             | Buttons / Input                  | User Response                  | CLI Behavior        |
|------------------|----------------------------------|--------------------------------|---------------------|
| `yes-no`         | Yes, No                          | `yes` or `no`                  | Blocks until response |
| `yes-no-cancel`  | Yes, No, Cancel                  | `yes`, `no`, or `cancel`       | Blocks until response |
| `ok`             | OK                               | `ok`                           | Blocks until response |
| `text`           | Text input + Send                | Free-form text                 | Blocks until response |
| `password`       | Password input + Send            | Free-form text (masked)        | Blocks until response |
| `choice`         | One button per option            | Selected option text           | Blocks until response |
| `choice-text`    | Option buttons + text input      | Selected option or typed text  | Blocks until response |
| `radio`          | Radio buttons + Submit           | Selected option (single)       | Blocks until response |
| `checkbox`       | Checkboxes + Submit              | Comma-separated selections     | Blocks until response |
| `toast`          | None (click to dismiss)          | `dismissed` (auto)             | Returns immediately   |

All interactive types show a centered modal overlay with a semi-transparent backdrop. The iframe (terminal, IDE, desktop) is blocked from interaction while the overlay is visible.

Toast notifications appear in the bottom-right corner without blocking interaction.

**Note:** `choice`, `choice-text`, `radio`, and `checkbox` all require the `--options` flag.

---

## Flags

### `--expires`

Sets how long a message remains active before timing out.

```bash
# Interactive message with 5 minute timeout
booth message send --title "Continue?" --body "Proceed with migration?" --type yes-no --expires 5m

# Toast that stays for 1 minute
booth message send --title "Heads up" --body "Maintenance in 10 minutes" --type toast --expires 1m
```

- **Interactive messages:** Default 10 minutes. If the user doesn't respond, the CLI exits with answer `timeout`.
- **Toast:** Default 30 seconds. The toast auto-dismisses when the timer expires.

### `--name`

Target a specific booth by name. If omitted, defaults to the current directory name (matching standard booth resolution).

```bash
booth message send --name my-project --title "Hello" --body "World" --type ok
```

---

## Toast Notifications

Toasts are non-blocking notifications that appear in the bottom-right corner of the booth UI.

- **Stackable** — Multiple toasts stack vertically (newest at bottom).
- **Auto-dismiss** — Each toast has a countdown progress bar and auto-dismisses when time expires (default: 30s).
- **Click to dismiss** — Users can click a toast to dismiss it early.
- **Fire-and-forget** — The CLI returns immediately after writing the message file. No response is expected.
- **No iframe blocking** — The user can continue working while toasts are visible.

```bash
# Quick notification (30s default)
booth message send --type toast --title "Build" --body "Build completed successfully."

# Longer notification
booth message send --type toast --title "Warning" --body "Disk usage above 80%" --expires 1m

# Stack multiple toasts
booth message send --type toast --title "Step 1" --body "Downloading dependencies..."
booth message send --type toast --title "Step 2" --body "Compiling source..."
booth message send --type toast --title "Step 3" --body "Running tests..."
```

---

## How It Works

### Architecture

All variants use a unified nginx wrapper pattern:

```
Browser --> nginx (:10000)
              |-- /              --> 302 redirect to /booth
              |-- /booth         --> wrapper HTML (iframe + message overlay)
              |-- /booth-messages/api/  --> bash+socat API server (:10007)
              |-- /*             --> inner service (variant-specific port)
```

The wrapper page embeds the variant's UI in an iframe and injects the message overlay HTML on top. A lightweight API server (bash + socat) handles message listing and response submission.

### Message Flow

1. **CLI writes a message file** to `.booth/.tmp/messages/<id>.msg.json` on the host (bind-mounted into the container).
2. **The overlay JS polls** `GET /booth-messages/api/list` every 2 seconds.
3. **The API server** reads `.msg.json` files and returns pending (unanswered) messages.
4. **The overlay renders** the appropriate UI (modal dialog or toast).
5. **User responds** (clicks a button, submits text, or toast auto-dismisses).
6. **The overlay POSTs** `POST /booth-messages/api/respond/<id>` with the answer.
7. **The API server writes** a `.response.json` file.
8. **The CLI detects** the response file and prints the answer (interactive types only).

### File Format

Message file (`.msg.json`):
```json
{
  "id": "msg-1234567890",
  "title": "Deploy?",
  "body": "Deploy to staging?",
  "type": "yes-no",
  "created": "2026-04-06T12:00:00Z",
  "expires": "2026-04-06T12:10:00Z"
}
```

Response file (`.response.json`):
```json
{
  "id": "msg-1234567890",
  "answer": "yes",
  "answered": "2026-04-06T12:00:15Z"
}
```

Message and response files are stored in `.booth/.tmp/messages/` and are cleaned up automatically when the booth restarts.

---

## Examples

### Scripting with booth messages

```bash
# Ask for confirmation before a destructive action
answer=$(booth message send --name dev-booth --title "Drop table?" \
  --body "This will delete all data in the users table." \
  --type yes-no --expires 1m | tail -1)

if [ "$answer" = "yes" ]; then
    echo "Dropping table..."
else
    echo "Cancelled."
fi
```

### Choice selection

```bash
answer=$(booth message send --name dev-booth --title "Environment" \
  --body "Select deployment target:" \
  --type choice --options "staging,production,rollback" \
  --expires 2m | tail -1)

echo "Selected: $answer"
```

### Choice with custom text input

```bash
# User can click a preset option or type their own
answer=$(booth message send --name dev-booth --title "Branch" \
  --body "Select or type a branch:" \
  --type choice-text --options "main,develop,release" \
  --expires 2m | tail -1)

echo "Branch: $answer"
```

### Radio buttons (single select)

```bash
answer=$(booth message send --name dev-booth --title "Log Level" \
  --body "Select log level:" \
  --type radio --options "debug,info,warn,error" \
  --expires 2m | tail -1)

echo "Level: $answer"
```

### Checkboxes (multi-select)

```bash
# Answer is comma-separated, e.g. "logging,metrics,tracing"
# Returns "none" if nothing selected
answer=$(booth message send --name dev-booth --title "Features" \
  --body "Select features to enable:" \
  --type checkbox --options "logging,metrics,tracing,profiling" \
  --expires 2m | tail -1)

echo "Enabled: $answer"
```

### Password prompt

```bash
secret=$(booth message send --name dev-booth --title "Auth Required" \
  --body "Enter your deploy key:" \
  --type password --expires 5m | tail -1)
```

### Toast from a build script

```bash
booth message send --type toast --title "Build started" --body "Compiling project..."

make build

booth message send --type toast --title "Build complete" --body "Ready to test."
```
