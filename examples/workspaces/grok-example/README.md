# Grok Build Example

This example is a minimal booth that has [Grok Build](https://x.ai/cli) (xAI's coding agent CLI, `grok`) preinstalled and reuses the `grok` login you already have on the host. Log in once on the host and every booth from this folder is logged in too. No installer script, no version wrangling: the Grok CLI is ready the moment the booth launches, in a clean, disposable sandbox isolated from the rest of your system.

**Use case: vet a repo before you run it.** Found a project on GitHub and not sure `npm install` or `make` on it is safe? `just vet <url>` clones it inside the booth, never onto your host, and has Grok review it with read-only tools. You get a report on what it does, what runs on install, what it reaches out to, and a verdict. See [Vet a repo before you run it](#vet-a-repo-before-you-run-it).

The same booth for other agents: [claude-example](../claude-example/), [codex-example](../codex-example/), [omp-example](../omp-example/).

**Stack:** Grok Build CLI

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/grok-example
booth

# 2. Inside the booth — start a Grok session
grok
```

### Log in on the host first

This booth uses the `credential` extension (selected by default with `grok`). It mounts your host's
Grok login into the booth, read-only. `.booth/config.toml` has:

```toml
run-args = [
    "-v", "~/.grok/auth.json:/etc/cb-home-seed/.grok/auth.json:ro",
    "-v", "~/.grok/config.toml:/etc/cb-home-seed/.grok/config.toml:ro"
]
```

- `~/.grok/auth.json` is your login, and `~/.grok/config.toml` your CLI settings. Both are copied
  into the booth's home once. After that, the booth keeps its own copy in its settings cache (see
  below), so changes made inside the booth stay in the booth.
- The rest of `~/.grok` (sessions, worktrees, downloads, logs) stays on the host.

1. **Log in on the host:**
   ```bash
   grok login
   ```
   Both files must exist before the booth starts. If one is missing, booth skips that mount
   (`Skipping volume mount: host path does not exist`), and Grok in the booth is not logged in.
2. **Start the booth:** `./booth`.
3. **Check the login arrived** (inside the booth): `[ -f ~/.grok/auth.json ] && echo ok`.

The login is copied only once, into the settings cache. If you log in again on the host, delete
`.booth/cache/home/coder/.grok/auth.json` so the next booth picks up the new one.

To use a console API key (`XAI_API_KEY`) instead of a host login, generate the booth with
`booth config --select 'grok+settings-cache+token-credential~credential'` and put
`XAI_API_KEY=...` in `.booth/.env`. The key is billed per use, not to a subscription.

### Run it

```bash
just --list
just version                 # grok --version
just grok                    # an interactive Grok session in the booth
just ask                     # one non-interactive task via scripts/ask-grok.sh
just ask "Summarise the Justfile"
just vet https://github.com/jonschlinkert/is-odd   # vet a repo -> reports/jonschlinkert-is-odd.md
```

`just ask` runs `scripts/ask-grok.sh`, which calls `grok -p` with read-only tools, prints the
answer and exits. It stops with a hint if no login is found.

### Example

Run from the host, `just ask` starts the booth, asks Grok, prints the answer, and stops the booth
again. `2>/dev/null` hides the booth's start/stop messages, so only the answer shows:

```console
$ just ask 'What is the day after Monday' 2>/dev/null
Tuesday.
```

## Vet a repo before you run it

Cloning a stranger's repository and running `npm install`, `pip install` or `make` runs their code
with your user's access to your files, SSH keys and cloud credentials. `just vet` lets Grok look
first, from inside the booth:

```bash
just vet https://github.com/owner/repo            # default branch
just vet https://github.com/owner/repo v2.1.0     # a branch or tag
```

`scripts/vet-repo.sh`:

1. Clones the repo (`--depth 1`) into a temporary folder in the booth's `/tmp`. The clone is
   never written to the project folder or the host, and it is deleted when the script ends.
2. Runs `grok -p` in the clone with only three tools: `--tools read_file,grep,list_dir`. Grok has
   no shell, no edit and no web access in that session (`--disable-web-search`), so nothing from
   the repository can execute. `--disallowed-tools search_tool,use_tool` also removes Grok's
   gateway to MCP tools, so a server from your own `~/.grok/config.toml` cannot be used either.
   The prompt opens with a line telling Grok the files are untrusted data, so instructions planted
   in them become a red flag instead of a command.
3. Prints the report and saves it to `reports/<owner>-<repo>.md`, with the URL and commit it
   vetted.

A repository can also carry agent configuration of its own: a `.mcp.json` or `.grok/config.toml`
that declares MCP servers, or a `.claude/settings.json` with hooks. These are programs, and an agent
that loads them runs the repository's code before reading a single file. This was checked with a
test repository that has all of them: Grok, run this way, started none.

The report always has the same sections: what it is, how to build and run it, what runs
automatically (install scripts, build hooks, git hooks, CI), network and secrets access, red flags,
and a verdict of **LOOKS FINE**, **REVIEW BEFORE RUNNING** or **DO NOT RUN**. Each finding cites
`file:line`. An excerpt of [reports/jonschlinkert-is-odd.md](reports/jonschlinkert-is-odd.md):

```console
$ just vet https://github.com/jonschlinkert/is-odd 2>/dev/null
# Vetting report: https://github.com/jonschlinkert/is-odd

Commit `a80ee0d831a8ee69f1fad5b4673491847975eb26`, vetted 2026-10-18.

## What runs automatically

Nothing in this tree runs on install or clone. `package.json` defines a single script, `test`
(`package.json:25-26`). There is no `preinstall`, `postinstall`, `prepare`, or other lifecycle
script, and no `Makefile`, `setup.py`, or `build.rs`.
...
## Verdict

LOOKS FINE. The checked-in code is the odd-integer check the README describes, with no install
hooks, no encoded or fetched execution, no bundled binaries, and no credential access.
```

This is a first look, not a guarantee. Grok reads only this repository, not the dependencies it
would pull in. If you do decide to run the project, the booth is a better place to try it than
your host.

## What's included

| Component      | Details |
|----------------|---------|
| Tool           | `grok` CLI (xAI's Grok Build coding agent) |
| Login          | `credential`: seeds the host's `~/.grok/auth.json` and `~/.grok/config.toml` |
| Settings cache | `settings-cache`: `~/.grok` in the booth is a cache folder, so the login, settings and sessions survive a booth restart |
| `just ask`     | `scripts/ask-grok.sh`: one `grok -p` task with read-only tools |
| `just vet`     | `scripts/vet-repo.sh`: clones a repo into the booth's `/tmp` and has Grok vet it with only `read_file`, `grep` and `list_dir`; writes `reports/<owner>-<repo>.md` |

Generated by `booth config --select grok+settings-cache` (`credential` comes with `grok` by
default). See "Log in on the host first" above for how Grok gets its login.
