# Oh My Pi Example

This example is a minimal booth that has [Oh My Pi](https://omp.sh) (`omp`, a terminal coding agent for 40+ model providers) preinstalled and reuses the `omp` login you already have on the host. Log in once on the host and every booth from this folder is logged in too. No installer script, no version wrangling: `omp` is ready the moment the booth launches, in a clean, disposable sandbox isolated from the rest of your system.

**Use case: vet a repo before you run it.** Found a project on GitHub and not sure `npm install` or `make` on it is safe? `just vet <url>` clones it inside the booth, never onto your host, and has omp review it with read-only tools. You get a report on what it does, what runs on install, what it reaches out to, and a verdict. See [Vet a repo before you run it](#vet-a-repo-before-you-run-it).

To log in with a Claude subscription token you pass in instead (no host login needed), see [omp-token-example](../omp-token-example/).

The same booth for other agents: [claude-example](../claude-example/), [codex-example](../codex-example/), [grok-example](../grok-example/).

**Stack:** Oh My Pi (`omp`)

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/omp-example
booth

# 2. Inside the booth — start an omp session
omp
```

### Log in on the host first

This booth uses the `credential` extension (selected by default with `oh-my-pi`). It mounts your
host's omp login into the booth, read-only. `.booth/config.toml` has:

```toml
run-args = [
    "-v", "~/.omp/agent/agent.db:/etc/cb-home-seed/.omp/agent/agent.db:ro",
    "-v", "~/.omp/agent/config.yml:/etc/cb-home-seed/.omp/agent/config.yml:ro"
]
```

- `~/.omp/agent/agent.db` holds the accounts you logged in to (OAuth tokens and API keys), and
  `~/.omp/agent/config.yml` your settings, including which model each role uses. Both are copied
  into the booth's home once. After that, the booth keeps its own copy in its settings cache (see
  below), so changes made inside the booth stay in the booth.
- The rest of `~/.omp` (sessions, logs, caches) stays on the host.

1. **Log in on the host:** run `omp`, then `/login`, and pick a provider (for example Anthropic,
   with a Claude subscription). `omp usage` lists the accounts you are logged in to; if it says
   `No credentials found`, the booth will have none either.
2. **Start the booth:** `./booth`.
3. **Check the login arrived** (inside the booth): `omp usage`.

The login is copied only once, into the settings cache. If you log in again on the host, delete
`.booth/cache/home/coder/.omp/agent/agent.db` so the next booth picks up the new one.

A model that runs on your host, such as one served by LM Studio or Ollama on `localhost`, is not
reachable from inside the booth: `localhost` there is the booth itself. omp then falls back to a
provider you are logged in to.

### Run it

```bash
just --list
just version                 # omp --version
just omp                     # an interactive omp session in the booth
just ask                     # one non-interactive task via scripts/ask-omp.sh
just ask "Summarise the Justfile"
just vet https://github.com/jonschlinkert/is-odd   # vet a repo -> reports/jonschlinkert-is-odd.md
```

`just ask` runs `scripts/ask-omp.sh`, which calls `omp -p` with read-only tools, prints the answer
and exits.

### Example

Run from the host, `just ask` starts the booth, asks omp, prints the answer, and stops the booth
again. `2>/dev/null` hides the booth's start/stop messages, so only the answer shows:

```console
$ just ask 'What is the day after Monday' 2>/dev/null
Tuesday.
```

## Vet a repo before you run it

Cloning a stranger's repository and running `npm install`, `pip install` or `make` runs their code
with your user's access to your files, SSH keys and cloud credentials. `just vet` lets omp look
first, from inside the booth:

```bash
just vet https://github.com/owner/repo            # default branch
just vet https://github.com/owner/repo v2.1.0     # a branch or tag
```

`scripts/vet-repo.sh`:

1. Clones the repo (`--depth 1`) into a temporary folder in the booth's `/tmp`. The clone is
   never written to the project folder or the host, and it is deleted when the script ends.
2. Runs `omp -p` in the clone with only three tools: `--tools read,grep,glob`. omp has no shell,
   no edit and no web access in that session. A system-prompt line tells omp the files are
   untrusted data, so instructions planted in them become a red flag instead of a command.
3. Prints the report and saves it to `reports/<owner>-<repo>.md`, with the URL and commit it
   vetted.

Restricting the tools is not enough on its own. omp also loads what a repository brings along:
extensions under `.omp/extensions/` (code omp runs), and MCP servers declared in `.mcp.json`,
`.codex/config.toml` and similar files (programs omp starts). Either would run the repository's
code before omp reads a single file. A test repository with all of them showed both happen with
`--tools` alone. The script turns them off:

| Flag | Stops |
|------|-------|
| `--no-extensions` | the repository's extensions |
| `--config scripts/omp-vet.yml` | the repository's MCP servers (`mcp.enableProjectConfig: false`) |
| `--no-lsp` | language servers starting on the repository's code |
| `--no-skills`, `--no-rules` | the repository's skill and rule files reaching the prompt |

With those, the same test repository ran nothing.

The report always has the same sections: what it is, how to build and run it, what runs
automatically (install scripts, build hooks, git hooks, CI), network and secrets access, red flags,
and a verdict of **LOOKS FINE**, **REVIEW BEFORE RUNNING** or **DO NOT RUN**. Each finding cites
`file:line`. An excerpt of [reports/jonschlinkert-is-odd.md](reports/jonschlinkert-is-odd.md),
which omp wrote with an xAI Grok model:

```console
$ just vet https://github.com/jonschlinkert/is-odd 2>/dev/null
# Vetting report: https://github.com/jonschlinkert/is-odd

Commit `a80ee0d831a8ee69f1fad5b4673491847975eb26`, vetted 2026-10-18.

## What runs automatically

- `package.json:27-29`: only `test` (`mocha`). No `preinstall`/`install`/`postinstall` or other
  lifecycle scripts.
...
## Verdict

LOOKS FINE. Matches the claimed odd-integer helper; no install hooks, no network/secret use in
code, no hidden payloads.
```

This is a first look, not a guarantee. omp reads only this repository, not the dependencies it
would pull in. If you do decide to run the project, the booth is a better place to try it than
your host.

## What's included

| Component      | Details |
|----------------|---------|
| Tool           | `omp` (Oh My Pi terminal coding agent) |
| Login          | `credential`: seeds the host's `~/.omp/agent/agent.db` and `~/.omp/agent/config.yml` |
| Settings cache | `settings-cache`: `~/.omp` in the booth is a cache folder, so the login, settings and sessions survive a booth restart |
| `just ask`     | `scripts/ask-omp.sh`: one `omp -p` task with read-only tools |
| `just vet`     | `scripts/vet-repo.sh`: clones a repo into the booth's `/tmp` and has omp vet it with only `read`, `grep` and `glob`; writes `reports/<owner>-<repo>.md` |

Generated by `booth config --select oh-my-pi+settings-cache` (`credential` comes with `oh-my-pi`
by default). See "Log in on the host first" above for how omp gets its login.
