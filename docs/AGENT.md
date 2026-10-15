# CodingBooth — Instructions for an AI Agent Inside a Booth

You are running inside a **booth**: a Docker container built for this project. The project folder
on the host is mounted at `/home/coder/code`, and you are the `coder` user. This page covers the jobs
you will be asked to do in here, in order: orient, run, install, configure, expose, set env vars,
write local templates. Each section ends with the local doc that goes deeper.

**Not in a booth?** (no `/opt/codingbooth/`, no `$BOOTH_CONTAINER_NAME`) Then this is the wrong guide —
read [AGENT_SETUP.md](https://github.com/NawaMan/CodingBooth/blob/main/docs/AGENT_SETUP.md), which
helps a user set a booth up from the host.

**Docs in here.** Every CodingBooth doc ships in `/opt/codingbooth/docs/` — `cat` it. For the user,
`viewmd /opt/codingbooth/docs &` serves them rendered on port 8765, opened like any server (§2). Online, the same files for this exact version are at
`https://github.com/NawaMan/CodingBooth/tree/$BOOTH_VERSION/docs` (an `--rc` or other pre-release
version has no tag; use `main`). The paths below are all local.

---

## 1. Orient yourself

```bash
booth--info                            # version, variant, booth name, how to reach the host
booth--envs                            # every BOOTH_* variable: port, variant, dind, egress, sudo, ...
head -2 ~/code/.booth/Boothfile        # "# Configured by: booth config ..." — what this booth was built from
[ -w ~/code/.booth ] && echo writable || echo read-only     # can you change the config yourself?
just --list                            # the project's own recipes, if it has a Justfile
```

What to expect, and what not to:

| | |
|---|---|
| **Persistent** | `/home/coder/code` (the host folder). Plus whatever `.booth/cache/` and `.booth/shared/` mount into `~`, and `--persist-home` if used. |
| **Gone when the container goes** | Everything else: `~` outside `code/`, `/usr`, `/etc`, `/opt`. A normal booth is removed on exit; a `--keep-alive` one survives until `./booth remove`. |
| **`.booth/`** | Read-only unless the booth was started with `--writable-booth`. `.booth/.tmp/` is always writable but is wiped on each start. |
| **sudo** | Passwordless — unless `BOOTH_SUDO=false` (`--no-sudo`). |
| **Languages** | Only what the Boothfile selected. The base image has no Python, no Node. |
| **docker** | Only when `BOOTH_DIND=true`. There is no docker otherwise, and no access to the host's. |
| **Network** | Open, unless `BOOTH_EGRESS=true` — then only allowlisted HTTP(S) domains (`.booth/egress/allowlist.txt`); ssh and raw TCP are blocked. |
| **git** | Installed. `~/.gitconfig` is usually empty: check `git config user.email` before committing, and ask rather than invent an identity. No ssh-agent is forwarded. |

Deeper: `/opt/codingbooth/docs/USER_GUIDE.md` (a working day in a booth), `IN-OUT.md` (every way
in and out), `BOOTH_SECURITY.md` (what the isolation does and does not do).

---

## 2. Run things

**Use the project's recipes.** If there is a `Justfile`, `just run` / `just test` / `just build`
is how this project is exercised — call those rather than inventing a parallel command.

**Showing the user a server you started** — say a dev server on port 5173:

| Variant (`$BOOTH_VARIANT_TAG`) | The user opens |
|---|---|
| `base` (Console UI), `codeserver`, `notebook` | `http://localhost:$BOOTH_HOST_PORT/proxy/5173/` — same login as the booth itself |
| `desktop-*` | `http://localhost:5173` in the browser on the booth's desktop |
| any, as a real host port | run `booth--expose 5173` (§5), then `http://localhost:5173` on the host |

`/proxy/` rewrites URLs on a best-effort basis; an app with hard-coded absolute asset paths may need
its base path set to `/proxy/5173/`. Binding to `127.0.0.1` is enough for the proxy and for
`booth--expose`.

**Reaching the host** — a database or API running outside the booth — is
`host.docker.internal:<port>` (also `$BOOTH_HOST_NAME`). The host service must listen on
`0.0.0.0`; one bound to `127.0.0.1` is unreachable from any container.

**Long-running work.** If `BOOTH_IDLE_TIME` is set (non-zero seconds), the booth shuts itself down
after that long without *user* input — your own activity does not count. On `base` it shuts down
with no warning. Before a long unattended task, check it and tell the user; on a web variant they
can pause the watchdog from the Booth panel. (`/opt/codingbooth/docs/BOOTH_IDLE.md`)

**Never run `booth--restart` or `booth--shutdown` on your own.** Both kill every process in the
booth, you included. See §4 for when a restart is needed and how to ask for one.

---

## 3. Install more things

**Right now, for this session** — you have sudo, and every installer the booth uses at build time is
on your `PATH`:

```bash
sudo apt--install.sh htop jq            # apt, pinned to the image's snapshot
sudo nodejs--setup.sh                   # a whole language/tool setup — ls /opt/codingbooth/setups/
sudo npm--install.sh cowsay             # also pip--, uv--, cargo--, go--, gem--install.sh, ...
                                        # (each needs its language set up first)
```

Start a new login shell (`bash -l`) after a setup so its `/etc/profile.d/` script is loaded. All of
this is lost when the container goes (§1), so it is for **trying** things.

**For good** — once it works, make it part of the Boothfile through `booth config` (§4):

| What you installed | What to select |
|---|---|
| a tool that has a setup in `/opt/codingbooth/setups/` | its template: `--add-select nodejs` (find the exact name with `./booth template search`) |
| apt packages | `--add-select 'apt-pkg:htop,jq'` |
| packages from another manager | its `*-pkg` extension, e.g. `--add-select 'python+pip-pkg:httpx'` — `./booth template show <lang>` lists them |
| anything else | a local setup (§7) |

**Read the setup before you use it.** `/opt/codingbooth/setups/<name>--setup.sh` is the source of
truth for where a tool lands, which env vars it sets, and which flags (versions) it takes — a
setup's flags are normally the template's params (`python--setup.sh 3.13.12` ⇢ `python:3.13.12`).

Deeper: `/opt/codingbooth/docs/BOOTH_CUSTOMIZATION.md`, `REPRODUCIBILITY.md` (pinning).

---

## 4. Change the booth's configuration

`.booth/Boothfile` (what goes into the image) and `.booth/config.toml` (how the container runs) are
**generated by `booth config`. Do not edit them by hand.** `.booth/.generated` holds their
fingerprint; a hand edit `booth config` cannot read back marks the files hand-written, after which
`booth config` refuses to run without `--overwrite` and the config TUI hides behind a warning. Every
change has a flag — use it. (Exception: a booth with no `.generated` and no `# Configured by:` line
was hand-written from the start; there, editing by hand is how it is maintained.)

**`booth config` works from in here.** The project's `./booth` wrapper is mounted at
`~/code/booth`; it downloads the CLI pinned in `.booth/tools/codingbooth.lock` on first use. Only
*starting* a booth is blocked inside a booth.

**Pass only the change.** A run starts from the command in the Boothfile's `# Configured by:` line,
and any setting you leave out keeps its recorded value:

```bash
cd ~/code
./booth config --no-tui --dryrun --add-select python     # print what would be written; touches nothing
./booth config --no-tui --overwrite --add-select python  # write it — needs a writable .booth/
```

| Change | Flag |
|---|---|
| add / drop a template or extension | `--add-select python`, `--add-select go+linter`, `--remove-select python` |
| an env var | `--add-env TZ=UTC`, `--remove-env TZ` |
| a published port | `--add-expose 8080`, `--add-expose +3000:5000` |
| a mount | `--add-mount ~/data:/home/coder/data` |
| variant | `--variant codeserver` (`base`, `notebook`, `codeserver`, `desktop-xfce`/`-kde`/`-lxqt`/`-wayland`) |
| booth port | `--port 10000` / `NEXT` / `RANDOM` |
| command | `--cmd npm --cmd start` (one word per flag; no `bash -lc` — booth wraps it already) |
| any other `config.toml` key | `--set <key>=<value>`, `--unset <key>` |

**A plain list flag replaces the whole list.** `--select python` alone drops every other template;
`--env`, `--expose` and `--mount` work the same way. Use the `--add-*` / `--remove-*` forms.

**If `.booth/` is read-only:** run the `--dryrun` to prove the command, then hand the user the
`--overwrite` form to run on the host. Or ask them to start the booth with `--writable-booth`.

**The change takes effect when the booth starts fresh.** Tell the user, and let them choose:

- a foreground booth: `booth--restart --yes` from in here (it ends your session too), or quit and
  run `./booth` on the host;
- `BOOTH_DAEMON=true`: `booth--restart` cannot bring it back — the user runs `./booth stop` then
  `./booth` on the host;
- `BOOTH_KEEP_ALIVE=true`: `./booth start` resumes the *old* image — the user needs `./booth remove`
  then `./booth`.

An older booth may have a `.booth/Dockerfile` instead of a Boothfile. If both exist, the Boothfile
wins and the Dockerfile is ignored. A Dockerfile-only booth has no `booth config` provenance, so it
is edited by hand.

Deeper: `/opt/codingbooth/docs/BOOTH_CONFIG.md` (every flag, the generated files),
`BOOTH_RUN.md` (every `config.toml` key), `BOOTH_LIFECYCLE.md` (start, stop, keep-alive),
`BOOTH_PROFILES.md` (`--profile` overlays).

---

## 5. Expose a port

| For | Do |
|---|---|
| now, until the booth stops | `booth--expose 5173` (host `localhost:5173`), `booth--expose 5173 15173`, `booth--expose 5173 +5173` (offset from the booth port) |
| see what is published and what is listening | `booth--expose list` |
| close it | `booth--expose close 5173` |
| every time the booth starts | `./booth config --no-tui --overwrite --add-expose 5173` (§4) |

`booth--expose` is TCP only and needs the host's `booth` process in the foreground (not a
`--daemon` booth). On a `--public` booth (`BOOTH_PUBLIC=true`) it is refused unless you pass
`--ok-public`, because the tunnel has none of the booth port's password or TLS — ask the user first.
Often you need no port at all: `/proxy/<port>/` (§2) already reaches the app.

Deeper: `/opt/codingbooth/docs/BOOTH_EXPOSE.md`.

---

## 6. Environment variables

| For | Do |
|---|---|
| what the booth tells you | `booth--envs` — `BOOTH_HOST_PORT`, `BOOTH_VARIANT_TAG`, `BOOTH_DIND`, `BOOTH_EGRESS`, ... (read-only facts) |
| this shell only | `export KEY=value` |
| every start, not secret | `./booth config --no-tui --overwrite --add-env KEY=value` → `config.toml` |
| every start, secret | a `KEY=value` line in `.booth/.env` |
| one profile only | `.booth/.<profile>--env` (used with `--profile <profile>`) |

`.booth/.env` is **not** generated, so editing it is fine (it lives in `.booth/`, so it needs
`--writable-booth` or the host). It must be gitignored — booth refuses to start if it is not, and
the generated `.booth/.gitignore` already covers it. Values are expanded on the **host** when the
booth starts: `TOKEN=$TOKEN` passes the host's variable through; `$VAR` and `~` work as in bash.
One `KEY=VALUE` per line, no spaces around `=`, no multi-line values.

All of these apply from the next start. If the user keeps secrets in `folio` (in every booth), use
them for one command without writing them anywhere: `folio exec --secrets <name> -- <cmd>`.

Deeper: `/opt/codingbooth/docs/BOOTH_VARS.md` (`.env` syntax and expansion), `BOOTH_PROFILES.md`.

---

## 7. Local templates, setups, and other files you may write

Everything under `.booth/` except `Boothfile`, `config.toml` and `.generated` is yours to write by
hand (writable `.booth/`, or on the host):

| Path | What it is |
|---|---|
| `.booth/setups/<name>--setup.sh` | a build-time install script; runs as root while the image builds |
| `.booth/templates/<name>.toml` | a project-local template, when a script alone is not enough |
| `.booth/startups/<name>--startup.sh` | runs as `coder` on every container start |
| `.booth/home/`, `.booth/home-seed/` | files copied into `~` on start — `home/` overwrites, `home-seed/` only fills in missing files |
| `.booth/cache/`, `.booth/shared/` | host folders bind-mounted at the matching path in the booth; `cache/` is gitignored, `shared/` is meant to be committed |

**A setup that is its own template.** Put a `# cb-template:` line in the script's leading comment
block and it becomes a template named after the file, selectable like any stock one — so the
`setup` line in the Boothfile is *generated*, not typed in:

```bash
#!/usr/bin/env bash
# cb-template: My Tool
# cb-disc:     Installs mytool, the project's release helper
# cb-band:     90
# cb-param:    TOOL_VERSION default=1.2.3
set -euo pipefail
TOOL_VERSION="${1:-1.2.3}"

curl -fsSL "https://example.com/mytool-${TOOL_VERSION}.tar.gz" | tar -xz -C /usr/local/bin mytool

# PATH or env for every shell: a profile script, named <LEVEL>-cb-<name>--profile.sh
cat > /etc/profile.d/65-cb-mytool--profile.sh <<'EOF'
export MYTOOL_HOME=/usr/local/share/mytool
EOF
```

```bash
./booth config --no-tui --overwrite --add-select mytool:1.3.0
# Boothfile:  arg TOOL_VERSION=1.3.0
#             setup mytool ${TOOL_VERSION}
```

- The value of each `cb-` key is **everything after the colon** — never put a comment on the same
  line. An unknown `cb-` key is an error. Other keys: `cb-detail`, `cb-requires`, `cb-tags`.
- `cb-band` orders it in the Boothfile (default 50; 90 runs after the language setups).
  `cb-param` values reach the script as `$1`, `$2`, ... in declaration order.
- `.booth/setups/` comes first on the build's `PATH`, so a script named after a built-in
  **replaces** it. Pick a new name unless replacing is the point.
- Profile/startup script `<LEVEL>` numbers run in order: pick one above what you depend on —
  `ls /etc/profile.d/ /usr/share/startup.d/` shows the ones in this booth (Python 53, Go 57, the
  JDK 60).

**`.booth/startups/` scripts** are `source`d one after another in one shell with `set -e`, in name
order (no `NN-` prefix counts as 50). An `exit` or a failing command stops the rest — keep them
short and put long-running servers in the background (`npm run dev &`).

Deeper: `/opt/codingbooth/docs/BOOTH_CUSTOMIZATION.md` (setup headers, local templates,
recipes), `AGENT_TEMPLATE.md` (every `template.toml` key), `BOOTH_SETUP.md` (setup-script
conventions and helpers), `BOOTH_HOME.md`, `BOOTH_LOCALCACHE.md`, `BOOTH_SHARED.md`.

---

## 8. Which templates exist for this version

The catalog is versioned with the CLI. `./booth template` downloads the templates for the version
pinned in `.booth/tools/codingbooth.lock` (from that GitHub release) and lists them, together with
this project's local ones:

```bash
cd ~/code
./booth template list                  # everything selectable, by category (--full adds secondary ones)
./booth template search postgres
./booth template show python           # params, extensions (+uv, +pip-pkg, ...), what it requires
./booth template cat python            # its full source
```

The source tree for a release is also browsable at
`https://github.com/NawaMan/CodingBooth/tree/<version>/templates`. The setup scripts the
templates call are already in this image, in `/opt/codingbooth/setups/`.

---

## Quick reference

| Don't | Do |
|---|---|
| hand-edit `.booth/Boothfile` or `config.toml` | `./booth config --no-tui --overwrite --add-…` (§4) |
| restate `--select` / `--env` / `--expose` with part of the list | `--add-*` / `--remove-*` |
| treat an ephemeral install as done | persist it through `booth config` (§3) |
| run `booth--restart` / `booth--shutdown` unasked | tell the user a restart is needed (§4) |
| put a secret in `config.toml` | `.booth/.env` (§6) |
| assume where a tool lives | read `/opt/codingbooth/setups/<name>--setup.sh` |
| commit as an invented identity | check `git config user.email`; ask |

| Symptom | Cause |
|---|---|
| `Read-only file system` under `.booth/` | started without `--writable-booth` (§4) |
| tool missing after a restart | it was installed ephemerally, or a restated `--select` dropped it, or a kept-alive booth was resumed on its old image |
| config change has no effect | the booth was not started fresh (§4) |
| `Running booth inside a booth container` | you tried to *start* a booth; `./booth config` and `./booth template` are fine |
| booth vanished during a long task | idle shutdown (§2) |
| `docker: command not found` | the booth has no DinD; `--add-select dind`, after asking — it gives the booth host-root-equivalent power |

Other docs in `/opt/codingbooth/`: `README.md` (product overview), `GUIDE.md` (the human's
in-booth guide: Booth panel, tiling, clipboard), `docs/` (everything), `variants/` (each image's
Dockerfile), `setups/` (every built-in setup and `booth--*` helper).
