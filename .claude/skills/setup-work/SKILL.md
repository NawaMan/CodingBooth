---
name: setup-work
description: Add, modify, or fix a setup script, template, or extension in the booth catalog — with a workspace to actually try the change in. Use when the user wants a new tool installable in a booth ("add a setup for X"), wants an existing one changed ("bump the default version", "expose a version knob", "add a VS Code extension to Y"), or reports something broken ("X fails to install", "the icon never appears", "the param is ignored").
---

# Work on a setup, template, or extension

The catalog is three layers, and a change usually touches more than one:

| Layer | Lives in | Is |
| --- | --- | --- |
| **Setup script** | `variants/base/setups/<name>--setup.sh` | how a tool gets into the image; `setup <name>` in a Boothfile compiles to `RUN <name>--setup.sh` |
| **Template** | `templates/<category>/<name>/template.toml` | how a user *selects* it from `booth config` |
| **Extension** | `templates/<category>/<parent>/<name>--extension.toml` | an add-on to a template — "X support for language Y" is almost always this |

**Two gates before the first write** (`AGENTS.md` Rules 0 and 0b — restated because this skill is
often loaded alone):

1. **Proposal before code** — post **Problem · Diagnostic · Approach** and wait. Which layers you
   will touch, which archetype, and which workspace the change gets tried in are all things the
   user should see first.
2. **Linked worktree** — `git worktree add worktree/<name> -b <name>`, work only there. A green
   light on the work is not permission to edit the main clone.

**Standing rule — end every turn by naming the try-it folder.** Once §2 has picked a workspace,
close each reply with the folder and the one command that exercises the change:

> 🧪 Try it: `examples/workspaces/zig-example` — `./booth -- ./run-primes.sh`

The user cannot check your work without that line. Repeat it every turn, not just the last one.

---

## 0. Which mode

| Mode | The user said | Go to |
| --- | --- | --- |
| **Add** | "add a setup for X", "make X selectable" | §1a → §2 → §3 → §4 → §5 → §6 |
| **Modify** | "bump the default", "expose a version knob", "add an extension to Y" | §1b → §2 → §3 → §4 → §5 → §6 |
| **Fix** | "X fails to build", "the param does nothing", "no icon appears" | §1c → §2 → §3 → §4 → §5 → §6 |

The middle sections are shared on purpose — the try-it loop is the same whichever mode you are in.

---

## 1a. Add — check it does not already exist

```bash
ls variants/base/setups/ | grep -i <name>          # the script
ls templates/*/ -d | grep -i <name>                # the selectable template
grep -rn "<name>" docs/TODO.md docs/TODO-*.md      # already planned / already rejected?
grep -rn "<name>" docs/CHANGELOG.md                # already shipped?
```

Near-misses matter. `build-essential` vs `gcc` is the standing example: one installs Ubuntu's
meta-package, the other pins a version into `/opt` with `update-alternatives`. Both exist on
purpose. If something close already exists, say what the new one adds before writing it — and
prefer extending the existing script's flags over a second script.

Check `variants/base/setups/future/` too — a script parked there was *tried and abandoned*
(`ocaml--setup.sh`). Do not resurrect one without saying so.

**Is it really a template?** If the thing is "X support for language Y" — a linter, a kernel, a VS
Code extension, a package list, a credential mount — it is an **extension** of the existing parent,
not a new template. Extensions are a single `<name>--extension.toml` file.

## 1b. Modify — find every place the thing is spelled

A change that touches only the script leaves the knob lying about it. Sweep all three layers before
editing:

```bash
grep -rn "<name>" variants/base/setups/            # script + siblings that call it
grep -rn "<name>" templates/                       # template, extensions, other templates' Boothfiles
grep -rn "<NAME>_VERSION" templates/ variants/     # the param, if there is one
```

**A version bump is three edits, not one** — they must move together or the guards fail and the
user's pin silently does nothing:

1. the script's own default (`REQ_VER="latest"`, or the pinned fallback),
2. `[params.<NAME>_VERSION] default` in `template.toml`,
3. the `suggests` list — put the new version first, drop the oldest.

If a param is added, it must be *referenced* as `${<NAME>_VERSION}` on the `setup` line in the same
template's directory, or `test88` fails. If a `setup <newname>` line is added, the script must
exist, or `test86` fails.

## 1c. Fix — reproduce before you edit

Do not patch from the symptom. Get the failure in front of you first — §2 will usually hand you a
workspace that already reproduces it.

| Symptom | Look at |
| --- | --- |
| Build fails at `RUN <name>--setup.sh` | the script; arch mapping, a moved release URL, an apt package rename |
| Tool missing on `PATH` at runtime | the profile script, and the `LEVEL` — a dependent installed below its prerequisite |
| Works in `base`, breaks in `codeserver`/`desktop-*` | a missing guard — `cb-has-vscode.sh` / `cb-has-desktop.sh` + `skip_setup` |
| Chosen version is ignored | a declared param nothing references — `test88`; check the `setup` line passes `${...}` |
| Arg style mismatch (`Unknown arg: 1.25.3`) | template emits positional but script wants `--version` (or vice versa) — `templates/README.md` §Setup Script Arguments |
| Desktop icon never appears | the setup does not call `cb-web-icon.sh` / `cb-desktop-icon.sh` — `test90` |
| Fails only on Apple Silicon / arm64 | arch bail-out must `exit 0` with an explanation, and the template needs `unsupported-arch` + note — `test92` |

State the root cause in one sentence before you write the fix. If the honest answer is "I am
guessing", say so and reproduce again instead.

---

## 2. Pick the workspace — the folder the user checks

**Every change gets a folder where it can be run.** Decide which, in this order:

**Adding something new → offer a workspace, and ask.**

> "I'll add `examples/workspaces/<name>-example` so this is exercisable — a small real project that
> uses `<name>`, plus a test. Want that, or should I use a throwaway folder instead?"

Do not create it unasked — `examples/workspaces/` is a published surface and ~60 entries deep.

**Fixing a bug → find the workspace that already covers it, and reuse it.**

```bash
grep -rln "<name>" examples/workspaces/*/.booth/Boothfile
grep -rln "<name>" tests/complex/*/.booth/Boothfile
```

A hit is the best possible try-it folder: it already reproduces, and a fix that makes *it* pass is
a fix with a witness. Say which one you picked and why.

**Modifying → reuse if a workspace covers the thing; otherwise throwaway.** A default-version bump
does not earn a new published example.

**User declines, or nothing fits → throwaway, no permission needed.** Build it in the scratchpad,
never in `examples/workspaces/`:

```bash
WS="$SCRATCH/<name>-try"          # scratchpad dir from the environment, not /tmp
mkdir -p "$WS/.booth"
```

Tell the user it is a throwaway and where it is. It still gets named every turn.

### Anatomy of a published workspace

Copy the shape of a small existing one (`zig-example` is a good model):

```
examples/workspaces/<name>-example/
├── .booth/
│   ├── config.toml                 # variant = "base"  (unless the tool needs an IDE/desktop)
│   └── Boothfile                   # setup <name> …
├── .cb-tests/
│   ├── tags.txt                    # one tag per line; runner filters on these
│   ├── test001-<thing>--on-host.sh # starts the booth, runs the in-booth suite
│   └── inBooth-test001-<thing>.sh  # the actual assertions, run inside
├── README.md                       # what it demonstrates, how to run it
└── <a small real project>          # source the tool actually operates on
```

Run it with the shared runner:

```bash
examples/workspaces/run-example-tests.sh --example <name>-example
```

---

## 3. Try it fast — no image rebuild

**This is the part most agents miss: you do not need to rebuild the repo's base image to try a
change.** Both layers have a local-override path.

### A changed setup script — copy it into the workspace

`setup <name>` resolves from the **project's** `.booth/setups/` before the image's
`/opt/codingbooth/setups/`. So the released base image runs *your* script:

```bash
mkdir -p "$WS/.booth/setups"
cp variants/base/setups/<name>--setup.sh "$WS/.booth/setups/"
# $WS/.booth/Boothfile:  setup <name>
(cd "$WS" && ./booth --silence-build -- <name> --version)
```

Edit the repo copy, re-copy, re-run. **Keep the two byte-identical** — the copy is the thing that
actually ran, so a drift means you verified something you are not shipping. Re-copy after every
edit; a `diff` at the end is cheap insurance.

### A changed template or extension — point at the repo tree, no Docker at all

```bash
export CB_TEMPLATES_PATH="$PWD/templates"       # or pass --templates-path each time

./codingbooth config "$WS" --no-tui --dryrun --select "<name>"
./codingbooth config "$WS" --no-tui --dryrun --select "<name>:1.72.0"    # check the pin lands
./codingbooth template show <name>                                       # metadata as the TUI sees it
./codingbooth template cat  <name>                                       # the segments it contributes, with orders
```

`--dryrun` prints the Boothfile and config it *would* write and touches nothing. This is a
sub-second loop — use it for every param, order, and `requires` question before going near Docker.
Build the binary first if it is stale: `./build/cli-build.sh` writes `./codingbooth`.

A project-local template also overrides a stock one of the same name (it prints a warning when it
shadows one), which is handy for trying a template shape without touching the repo tree:

```
$WS/.booth/templates/<category>/<name>/template.toml   + a meta.toml in the category dir
```

### Then, and only then, the real thing

```bash
(cd "$WS" && ./booth --silence-build -- <the command a user would actually run>)
```

**Booth hygiene:** check `./booth list` before starting something long-lived, tear down only the
containers *you* started, and never stop one you did not. If Docker is down, say so — do not
invent a host fallback.

---

## 4. Write it

### Adding a setup script — pick the archetype

Copy the closest **real** script; `template-seup.sh` is only the heaviest shape's scaffold and is
the wrong default for most tools.

| Shape | Use when | Copy from |
| --- | --- | --- |
| **Single release binary** *(default)* | One binary from a GitHub release | `lazygit--setup.sh`, `buf--setup.sh` |
| **Versioned toolchain** | A language/runtime users pin a version of | `go--setup.sh` |
| **apt meta-package** | Ubuntu already packages it well | `build-essential--setup.sh` |
| **Guarded add-on** | Only meaningful when a host tool exists (VS Code ext, notebook kernel, desktop app) | `go-code-extension--setup.sh`, `go-nb-kernel--setup.sh` |

**Single release binary** — arch-map, resolve `latest` from the GitHub API or take `--version`,
`install -m 755` into `/usr/local/bin`. No profile, no startup, **no LEVEL**. Most tools land here.

**Versioned toolchain** — install to `/usr/local/<tool>-${VERSION}`, point `/usr/local/<tool>-current`
at it with `ln -sfn`, then emit the trio. The `-current` symlink is what lets the last install win
without rewriting the profile.

**apt meta-package** — `DEBIAN_FRONTEND=noninteractive`, `apt-get update`, `--no-install-recommends`,
then `rm -rf /var/lib/apt/lists/*` in the same layer. Do **not** pin `pkg=version` and call it
reproducible: Ubuntu's pool keeps only the current build, so the pin breaks on the next security
rebuild. Reproducibility for apt comes from `APT_SNAPSHOT` (`docs/REPRODUCIBILITY.md` Tier 2).

**Guarded add-on** — must exit *gracefully* when its host is absent, or every base-variant build
breaks. `skip_setup` exits 0 under a Dockerfile build (no TTY) and 42 interactively; never `exit 1`
for "not applicable". Full helper reference — `skip-setup`, `cb-has-*`, `code-extension-source`,
`cb-web-icon` / `cb-desktop-icon` — is `docs/BOOTH_SETUP.md` §Shared helpers.

### Script non-negotiables

- Apache license header (copy verbatim from a sibling), then `set -Eeuo pipefail` and
  `trap 'echo "❌ Error on line $LINENO"; exit 1' ERR`.
- Root check: `[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }`, then `HOME=/root`
  when anything writes to `$HOME` — build-time root is not the runtime user.
- `usage()` with real examples when the script takes flags. Two arg styles exist and both are fine
  — positional (`go--setup.sh 1.25.3`) and flag (`--version X|latest`). **Match whatever the
  `template.toml` emits** — a mismatch is the `Unknown arg` bug in §1c.
- Arch handling: map `x86_64|amd64` and `aarch64|arm64`, fail loudly on anything else. Sources
  differ — `dpkg --print-architecture` vs `uname -m`; pick what the release assets are named after.
- Closing summary: `✅ <tool> installed.`, the version echoed back, then a `ℹ️ Ready to use:`
  heredoc with the two or three commands a user actually types. This is the tool's only in-booth
  documentation.

Emit the **trio** only if the tool needs it (`docs/BOOTH_SETUP.md` is the reference):

| Artifact | Path | Runs | chmod |
| --- | --- | --- | --- |
| Startup | `/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh` | once per container start, as the user | 755 |
| Profile | `/etc/profile.d/<LEVEL>-cb-<name>--profile.sh` | every shell login | 644 |
| Starter | `/usr/local/bin/<name>` | every invocation | 755 |

`LEVEL`: 50–54 core, 55–59 OS/UI, 60–64 languages, 65–69 language extensions, 70–74 dev tools,
75–79 plugins/kernels. Lower = prerequisite. Startup code must be idempotent (sentinel file);
profile code must be cheap and PATH-guarded. Values are stamped in with `envsubst '$VAR'` over a
quoted `<<'EOF'` heredoc — quoted so the *runtime* `$HOME`/`$PATH` survive, `envsubst` so
build-time versions are baked.

Nothing registers the script: `variants/base/Dockerfile` copies the whole directory to
`/opt/codingbooth/setups/`, which is on `PATH`.

### Making it selectable — the template

```toml
# templates/<category>/<name>/template.toml
display-name   = "Lazygit"
display-disc   = "Simple terminal UI for git commands"
display-detail = "Longer paragraph shown in the TUI detail pane."
display-order  = 60
tags = ["git", "tui", "cli"]

[params.BUF_VERSION]
default  = "latest"
suggests = ["latest", "1.72.0"]

[segments]
Boothfile = """
setup buf --version ${BUF_VERSION}
"""
```

Categories: `languages`, `tools`, `ides`, `databases`, `browsers`, `desktops`, `ai-tools`,
`education`. The loader scans the tree — there is no index to update.

**An extension instead** when the thing is an add-on to an existing entry — a single
`<name>--extension.toml` beside the parent's `template.toml`. May set `auto-select = true` and
`requires = ["notebook"]`. Selection syntax is `go/protobuf+go`.

Which **order band** the Boothfile segment belongs in (`Boothfile--60` for things needing an IDE,
`--65` for VS Code extensions, `--70` for kernels, `--90` for post-setup) is
`templates/README.md`. Every schema key is `docs/AGENT_TEMPLATE.md`.

---

## 5. Test it

### The standard: make the tool *do* the thing

`docs/TODO-SETUP_PROOF.md` audited this and found 109 of 182 catalog setups have no runtime test
and only 14 are proven functional. The bar it sets, and the bar for anything you touch:

> A test should make the tool do what a user would do with it in the first five minutes.
> Installing a compiler and only running `gcc --version` proves a file landed on `PATH`, not that
> it can compile.

Write the **functional** assertion — compile and run a program, execute a script, serve and answer
a request, run a query. Fall back to `--version` only when nothing else is meaningful (a
credential helper, a pure library), and say so in the test's comment.

### Complex test — `tests/complex/test-boothfile-<name>/`

Auto-discovered by directory name:

```
.booth/config.toml                    variant = "base"
.booth/Boothfile                      setup <name>
.booth/setups/<name>--setup.sh        ← copy of the script
test--boothfile-<name>.sh             sources ../../common--source.sh
```

**The copy under `.booth/setups/` is mandatory and is not redundant** — the same mechanism §3 uses.
Tests run against the *released* base image, which does not ship your script yet. Note it in a
Boothfile comment, as `tests/complex/test-boothfile-binary-companions/.booth/Boothfile` does, and
keep the copy byte-identical.

```bash
ACTUAL=$(run_coding_booth --silence-build -- bash -c 'cd /tmp && <compile-and-run something>')
if echo "$ACTUAL" | grep -qE "<expected output>"; then
    print_test_result "true"  "$0" "1" "<name> compiles and runs a program"
else
    print_test_result "false" "$0" "1" "<name> should compile and run a program"
    FAILED=$((FAILED + 1))
fi
```

### Config test — `tests/config/test<NN>-init-<name>.sh`

Next free number (`ls tests/config | tail -3`), using `begin` / `run` / `assert-line` / `finally`
from `test-helpers--source.sh`. Assert the `setup`/`install` line and the version pin, default and
pinned:

```bash
run booth config $prj --no-tui --select "<name>:1.72.0"
assert-line "$prj/.booth/Boothfile" "arg <NAME>_VERSION=" '1.72.0' "<name> version pin"
```

### Catalog guards — run after any template change

Cheap, no Docker, and they catch what a single-template test cannot:

```bash
tests/config/test86-all-setups-exist.sh              # every `setup <name>` has a script
tests/config/test88-all-params-are-wired.sh          # every declared param is referenced
tests/config/test90-web-servers-have-desktop-icon.sh # web servers register an icon
tests/config/test92-arch-unsupported-is-declared.sh  # unsupported-arch carries a note
```

### Run only what you touched

```bash
tests/config/test<NN>-init-<name>.sh
(cd tests/complex/test-boothfile-<name> && ./test--boothfile-<name>.sh)   # needs Docker; builds an image
examples/workspaces/run-example-tests.sh --example <name>-example         # if you made one
```

---

## 6. Document it

- **`docs/CHANGELOG.md`** — required. New bullet at the top of `## Unreleased`, house style: bold
  lede sentence naming the change, then what it unblocks and how to select it. A bug fix says what
  was broken and who was affected, not just what changed.
- **`docs/BOOTH_CONFIG.md`** — only if the tool joins an existing catalog table.
- **`docs/TODO.md`** — if this closes an open `- [ ]`, tick it in the same change.
- **`docs/TODO-SETUP_PROOF.md`** — if you upgraded a setup from presence-tested to
  functionally-tested, move it in the audit.

`docs/AGENT_SETUP.md`'s "Common ones" list is a short illustrative sample, not a registry — leave
it alone unless the tool is genuinely a headline one.

---

## Done means

The change, its tests passing, the guards passing, the CHANGELOG entry — **and a folder the user
can open to see it work.** Report what you ran and what you skipped; "the complex test needs Docker
and I did not run it" is a fine outcome to state, and not one to paper over.

Close with the try-it line:

> 🧪 Try it: `<workspace>` — `<command>`
