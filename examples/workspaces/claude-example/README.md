# Claude Code Example

This example is a minimal booth that has [Claude Code](https://docs.claude.com/en/docs/claude-code) preinstalled and reuses the `claude` login you already have on the host. Log in once on the host and every booth from this folder is logged in too. No Node setup, no `npm install -g`, no version wrangling: the Claude Code CLI is ready the moment the booth launches, in a clean, disposable sandbox isolated from the rest of your system.

**Use case: vet a repo before you run it.** Found a project on GitHub and not sure `npm install` or `make` on it is safe? `just vet <url>` clones it inside the booth, never onto your host, and has Claude review it with read-only tools. You get a report on what it does, what runs on install, what it reaches out to, and a verdict. See [Vet a repo before you run it](#vet-a-repo-before-you-run-it).

To log in with a token you pass in instead (no host login needed), see [claude-token-example](../claude-token-example/).

**Stack:** Claude Code CLI

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/claude-example
booth

# 2. Inside the booth — start a Claude Code session
claude
```

### Log in on the host first

This booth uses the `credential` extension (selected by default with `claude-code`). It mounts your
host's Claude Code login into the booth, read-only. `.booth/config.toml` has:

```toml
run-args = [
    "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",
    "-v", "~/.claude/.credentials.json:/etc/cb-home/.claude/.credentials.json:ro"
]
```

- `~/.claude/.credentials.json` is your login. It is placed in the booth's home on every start, so
  the booth always uses the host's current login.
- `~/.claude.json` holds Claude Code's settings and onboarding state. It is copied into the booth's
  home only once, so changes made inside the booth stay in the booth.

1. **Log in on the host** (a Pro/Max/Team/Enterprise subscription or an Anthropic Console account):
   ```bash
   claude          # then /login, and follow the browser prompt
   ```
   Both files must exist before the booth starts. If one is missing, booth skips that mount
   (`Skipping volume mount: host path does not exist`), and Claude Code in the booth is not
   logged in.
2. **Start the booth:** `./booth`.
3. **Check the login arrived** (inside the booth): `[ -f ~/.claude/.credentials.json ] && echo ok`.

If Claude in the booth says `OAuth session expired and could not be refreshed`, the login in the
host's `~/.claude/.credentials.json` is out of date. That can happen even while `claude` works on
the host, if the host logs in some other way (an API key, for example). Run `claude` and `/login`
on the host again, then start a fresh booth.

On macOS, Claude Code keeps the login in the Keychain, not in `~/.claude/.credentials.json`, so
there is nothing to mount. Use [claude-token-example](../claude-token-example/) there.

### Run it

```bash
just --list
just version                 # claude --version
just claude                  # an interactive Claude Code session in the booth
just ask                     # one non-interactive task via scripts/ask-claude.sh
just ask "Summarise the Justfile"
just vet https://github.com/jonschlinkert/is-odd   # vet a repo -> reports/jonschlinkert-is-odd.md
```

`just ask` runs `scripts/ask-claude.sh`, which calls `claude -p` with read-only tools, prints the
answer and exits. It stops with a hint if no login is found.

### Example

Run from the host, `just ask` starts the booth, asks Claude, prints the answer, and stops the booth
again. `2>/dev/null` hides the booth's start/stop messages, so only the answer shows:

```console
$ just ask 'What is the day after Monday' 2>/dev/null
The day after Monday is **Tuesday**.

$ just ask 'What is the expected temperature in Bangkok tomorrow.' 2>/dev/null
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

## Vet a repo before you run it

Cloning a stranger's repository and running `npm install`, `pip install` or `make` runs their code
with your user's access to your files, SSH keys and cloud credentials. `just vet` lets Claude look
first, from inside the booth:

```bash
just vet https://github.com/owner/repo            # default branch
just vet https://github.com/owner/repo v2.1.0     # a branch or tag
```

`scripts/vet-repo.sh`:

1. Clones the repo (`--depth 1`) into a temporary folder in the booth's `/tmp`. The clone is
   never written to the project folder or the host, and it is deleted when the script ends.
2. Runs `claude -p` in the clone with `--tools "Read,Glob,Grep"`. In that session Claude has no
   Bash, no Edit and no web access, so nothing from the repository can execute, even though this
   booth's `auto-accept` settings allow more. A system-prompt line tells Claude the files are
   untrusted data, so instructions planted in them become a red flag instead of a command.
3. Prints the report and saves it to `reports/<owner>-<repo>.md`, with the URL and commit it
   vetted.

The report always has the same sections: what it is, how to build and run it, what runs
automatically (install scripts, build hooks, git hooks, CI), network and secrets access, red flags,
and a verdict of **LOOKS FINE**, **REVIEW BEFORE RUNNING** or **DO NOT RUN**. Each finding cites
`file:line`. An excerpt:

```console
$ just vet https://github.com/jonschlinkert/is-odd 2>/dev/null
# Vetting report: https://github.com/jonschlinkert/is-odd

Commit `a80ee0d831a8ee69f1fad5b4673491847975eb26`, vetted 2026-10-18.

## What runs automatically
- **npm lifecycle scripts:** none. The only script is `test` (`package.json:25-27`), with no
  `preinstall`, `install`, `postinstall` or `prepare`.
...
## Verdict
**LOOKS FINE.** The code is 13 lines of plain JavaScript (`index.js:12-24`), with no install
hooks, no network access and no access to credentials.
```

This is a first look, not a guarantee. Claude reads only this repository, not the dependencies it
would pull in. If you do decide to run the project, the booth is a better place to try it than
your host.

## What's included

| Component      | Details |
|----------------|---------|
| Tool           | `claude` CLI (Anthropic's official terminal agent) |
| Login          | `credential`: mounts the host's `~/.claude.json` and `~/.claude/.credentials.json` read-only |
| Accept edits   | `auto-accept`: `.booth/home-seed/.claude/settings.json` lets Claude use its tools (Bash, Edit, WebSearch, ...) without asking, but denies destructive git commands; a startup hook also protects mounted volumes from `rm -rf` |
| Settings cache | `settings-cache`: `~/.claude` in the booth is a cache folder, so settings, history and sessions survive a booth restart |
| `just ask`     | `scripts/ask-claude.sh`: one `claude -p` task with read-only tools |
| `just vet`     | `scripts/vet-repo.sh`: clones a repo into the booth's `/tmp` and has Claude vet it with only `Read`, `Glob` and `Grep`; writes `reports/<owner>-<repo>.md` |

Generated by `booth config --select claude-code+auto-accept+settings-cache` (`credential` comes
with `claude-code` by default). See "Log in on the host first" above for how Claude Code gets its login.
