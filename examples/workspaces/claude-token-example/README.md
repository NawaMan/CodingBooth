# Claude Code Example (token login)

This example is a minimal booth that has [Claude Code](https://docs.claude.com/en/docs/claude-code) preinstalled and logs in with a token. You create a long-lived token on the host with `claude setup-token` and pass it into the booth as `CLAUDE_CODE_OAUTH_TOKEN`. The booth never sees your host's Claude login files. No Node setup, no `npm install -g`, no version wrangling: the Claude Code CLI is ready the moment the booth launches, in a clean, disposable sandbox isolated from the rest of your system.

Use this example when the host has no `claude` login to share (CI, a server, macOS where the login lives in the Keychain), or when you want the booth to hold only a token you can revoke. To reuse the host's `claude` login instead, see [claude-example](../claude-example/).

**Stack:** Claude Code CLI

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/claude-token-example
booth

# 2. Inside the booth — start a Claude Code session
claude
```

### Get a token and pass it to the booth

This booth uses the `token-credential` extension: Claude Code logs in with a long-lived
`CLAUDE_CODE_OAUTH_TOKEN` instead of a host login. `.booth/config.toml` forwards it into the container:

```toml
run-args = ["-e", "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}"]
```

`${...}` is expanded **on the host** when the booth starts, so the variable must exist there first.

1. **Create the token** (needs a Pro/Max/Team/Enterprise subscription, not API billing). On the host:
   ```bash
   claude setup-token
   ```
   Log in in the browser; it prints a token (`sk-ant-oat01-...`). Copy it, it is shown once.
2. **Make it available to the booth**, either way:
   - Export it in the shell that starts the booth:
     ```bash
     export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
     ./booth
     ```
   - Or put a line `CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...` in `.booth/.env`
     (gitignored; booth refuses to start if it is not). Values there are also expanded on the host,
     so `CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN` passes through your host variable.
3. **Check it arrived** (inside the booth): `[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && echo ok`.
   If empty, the variable was not set on the host when the booth started. Set it and start a fresh booth.

Never put the token in `config.toml`, the Justfile or any committed file.

### Run it

```bash
just --list
just version                 # claude --version
just claude                  # an interactive Claude Code session in the booth
just ask                     # one non-interactive task via scripts/ask-claude.sh
just ask "Summarise the Justfile"
just ask --quiet "Summarise the Justfile"   # print only the answer
```

`just ask` runs `scripts/ask-claude.sh`, which calls `claude -p` with read-only tools, prints the
answer and exits. It stops with a hint if the token is missing.

### One prompt without `just`

`./booth -- <command>` runs a command in a fresh booth and exits. The words after `--` are joined
with spaces and run with `bash -lc`, so your shell's quotes are removed before the booth sees
them. Quote the prompt twice:

```console
$ ./booth -- claude -p "'What day is after Monday?'"
Info: compiling Boothfile '.../claude-token-example/.booth/Boothfile'...
Info: image 'codingbooth-local:claude-token-example-base-0.83.0--rc1' is up to date, skipping the build.
Tuesday comes after Monday.
```

With only one layer of quotes (`./booth -- claude -p 'What day is after Monday?'`), `bash -lc`
gets `claude -p What day is after Monday?`, and Claude receives just `What` as the prompt.
`just ask` adds the second layer for you.

#### Giving it the token

`CLAUDE_CODE_OAUTH_TOKEN` must be set on the host when the booth starts.

1. **Get the token** (once). On the host, run `claude setup-token`, log in in the browser, and
   copy the `sk-ant-oat01-...` token it prints. It is shown only once. This needs a
   Pro/Max/Team/Enterprise subscription, not API billing.
2. **Pass it to the command**, either way:

   - **Directly**, as a variable for this one command:
     ```bash
     CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... ./booth -- claude -p "'What day is after Monday?'"
     ```
     The token ends up in your shell history this way. To keep it out, read it in without echo
     first: `read -rs CLAUDE_CODE_OAUTH_TOKEN && export CLAUDE_CODE_OAUTH_TOKEN`, then run
     `./booth -- ...` as usual.

   - **From [EnvFolio](https://github.com/NawaMan/EnvFolio)**, which keeps the token encrypted and
     gives it only to the command you run. Store it once:
     ```bash
     folio insert secret claude/code-oauth-token    # paste the token; asked twice, no echo
     ```
     Then run:
     ```bash
     folio exec -s claude -- ./booth -- claude -p "'What day is after Monday?'"
     ```
     `-s` loads secrets, and `claude` loads every entry in that folder. `folio` names the
     variable after the entry's path, so `claude/code-oauth-token` becomes
     `CLAUDE_CODE_OAUTH_TOKEN`.

### Example

Run from the host, `just ask` starts the booth, asks Claude, prints the answer, and stops the booth
again. `--quiet` hides the booth's start/stop messages, so only the answer shows (errors, such as
a missing login, still print):

```console
$ just ask --quiet 'What is the day after Monday'
The day after Monday is **Tuesday**.

$ just ask --quiet 'What is the expected temperature in Bangkok tomorrow.'
Bangkok should be hot and humid tomorrow (Monday, Oct 19), with a high of about 32–34°C and a low
of about 22–26°C. The sources vary a little on the exact numbers.

- **AccuWeather:** high about 34°C, low about 26°C, partly cloudy with scattered thunderstorms and
  a 55% chance of rain.
- **Thai Meteorological Department:** isolated to scattered thundershowers through Oct 19. It also
  warns of possible heavy rain and flash flooding in the Bangkok area.

Take an umbrella, especially for the afternoon and evening, when storms are most likely.

Sources:
- [Thai Meteorological Department 7-day forecast](https://www.tmd.go.th/en/forecast/sevenday)
- [AccuWeather: Bangkok tomorrow](https://www.accuweather.com/en/th/bangkok/318849/weather-tomorrow/318849)
```

The second answer needed a live web search. `auto-accept` allows `WebSearch`, so Claude in the
booth can look things up online, not just read your files.

## What's included

| Component      | Details |
|----------------|---------|
| Tool           | `claude` CLI (Anthropic's official terminal agent) |
| Login          | `token-credential`: forwards `CLAUDE_CODE_OAUTH_TOKEN` from the host; `~credential` drops the host-file mount |
| Accept edits   | `auto-accept`: `.booth/home-seed/.claude/settings.json` lets Claude use its tools (Bash, Edit, WebSearch, ...) without asking, but denies destructive git commands; a startup hook also protects mounted volumes from `rm -rf` |
| Settings cache | `settings-cache`: `~/.claude` in the booth is a cache folder, so settings, history and sessions survive a booth restart |
| `just ask`     | `scripts/ask-claude.sh`: one `claude -p` task with read-only tools |

Generated by `booth config --select 'claude-code+auto-accept+settings-cache+token-credential~credential'`.
`token-credential` forwards the token and `~credential` turns off the default host-login mount. See
"Get a token" above for how Claude Code gets its login.
