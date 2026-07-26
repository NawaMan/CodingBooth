---
name: setup-add
description: Add a new setup script to variants/base/setups/ in the house style — the script, its template.toml so it is selectable in `booth config`, its complex + config tests, and the CHANGELOG entry. Use when the user wants a new tool installable in a booth ("add a setup for X", "make X available in booths", "add X to the catalog").
---

# Add a setup

A setup is how a tool gets into a booth image: `setup <name>` in a Boothfile compiles to
`RUN <name>--setup.sh` (`cli/src/pkg/boothfile`). Adding one is **five files, not one** — a script
nobody can select from `booth config` is half a feature.

**Two gates before the first write** (`AGENTS.md` Rules 0 and 0b — restated because this skill is
often loaded alone):

1. **Proposal before code** — post **Problem · Diagnostic · Approach** and wait. "Add a setup for
   X" is a request, not an approved plan: the archetype (§2), the version story, and whether this
   deserves its own template or an `--extension.toml` are all things the user should see first.
2. **Linked worktree** — `git worktree add worktree/<name> -b <name>`, work only there. A green
   light on the work is not permission to edit the main clone.

## 1. Check it does not already exist

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

Also check `variants/base/setups/future/` — a script parked there was *tried and abandoned*
(`ocaml--setup.sh`). Do not resurrect one without saying so.

## 2. Pick the archetype

Four shapes are actually in use. Copy the closest **real** script; `template-seup.sh` is only the
heaviest shape's scaffold and is the wrong default for most tools.

| Shape | Use when | Copy from |
| --- | --- | --- |
| **Single release binary** *(default)* | One binary from a GitHub release | `lazygit--setup.sh`, `buf--setup.sh` |
| **Versioned toolchain** | A language/runtime users pin a version of | `go--setup.sh` |
| **apt meta-package** | Ubuntu already packages it well | `build-essential--setup.sh` |
| **Guarded add-on** | Only meaningful when a host tool exists (VS Code ext, notebook kernel, desktop app) | `go-code-extension--setup.sh`, `go-nb-kernel--setup.sh` |

**Single release binary** — arch-map, resolve `latest` from the GitHub API or take `--version`,
`install -m 755` into `/usr/local/bin`. No profile, no startup, **no LEVEL**. Most tools land here.

**Versioned toolchain** — install to `/usr/local/<tool>-${VERSION}`, point `/usr/local/<tool>-current`
at it with `ln -sfn`, then emit the trio (§3). The `-current` symlink is what lets the last install
win without rewriting the profile.

**apt meta-package** — `DEBIAN_FRONTEND=noninteractive`, `apt-get update`, `--no-install-recommends`,
then `rm -rf /var/lib/apt/lists/*` in the same layer. Do **not** pin `pkg=version` and call it
reproducible: Ubuntu's pool keeps only the current build, so the pin breaks on the next security
rebuild. Reproducibility for apt comes from `APT_SNAPSHOT` (`docs/REPRODUCIBILITY.md` Tier 2), which
`booth config` sets — the setup script just installs.

**Guarded add-on** — must exit *gracefully* when its host is absent, or every base-variant build
breaks:

```bash
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then          # or cb-has-desktop.sh
    skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
fi
```

`skip_setup` exits 0 under a Dockerfile build (no TTY) and 42 interactively. Never `exit 1` for
"not applicable". VS Code extensions then `source libs/code-extension-source.sh` and call
`install_extensions <ext-id>` — it handles both `code` and `code-server`, and defers under QEMU.

## 3. Write the script — `variants/base/setups/<name>--setup.sh`

Non-negotiables, taken from what every script in the directory already does:

- Apache license header (copy verbatim from a sibling), then `set -Eeuo pipefail` and
  `trap 'echo "❌ Error on line $LINENO"; exit 1' ERR`.
- Root check: `[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }`, then `HOME=/root`
  when anything writes to `$HOME` — build-time root is not the runtime user.
- `usage()` with real examples when the script takes flags. Two arg styles exist and both are fine
  — positional (`go--setup.sh 1.25.3`, used by templates that pass `${GO_VERSION}`) and flag
  (`--version X|latest`, used by `lazygit`/`buf`). **Match whatever the `template.toml` will emit.**
- Arch handling: map `x86_64|amd64` and `aarch64|arm64`, fail loudly on anything else. Sources
  differ — `dpkg --print-architecture` (lazygit) vs `uname -m` (buf); pick what the release assets
  are named after.
- Closing summary: `✅ <tool> installed.`, the version echoed back, then a `ℹ️ Ready to use:`
  heredoc with the two or three commands a user actually types. This block is the tool's only
  in-booth documentation.

Emit the **trio** only if the tool needs it (`docs/BOOTH_SETUP.md` is the reference):

| Artifact | Path | Runs | chmod |
| --- | --- | --- | --- |
| Startup | `/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh` | once per container start, as the user | 755 |
| Profile | `/etc/profile.d/<LEVEL>-cb-<name>--profile.sh` | every shell login | 644 |
| Starter | `/usr/local/bin/<name>` | every invocation | 755 |

`LEVEL` matters only here: 50–54 core, 55–59 OS/UI, 60–64 languages, 65–69 language extensions,
70–74 dev tools, 75–79 plugins/kernels. Lower = prerequisite. Startup code must be idempotent
(sentinel file); profile code must be cheap and PATH-guarded:

```bash
case ":$PATH:" in *":/usr/local/<name>-current/bin:"*) ;; *) export PATH="/usr/local/<name>-current/bin:$PATH";; esac
```

Values are stamped in with `envsubst '$VAR'` over a quoted `<<'EOF'` heredoc — quoted so the
*runtime* `$HOME`/`$PATH` survive, `envsubst` so build-time versions are baked.

Nothing registers the script: `variants/base/Dockerfile` copies the whole directory to
`/opt/codingbooth/setups/`, which is on `PATH`.

## 4. Make it selectable — `templates/<category>/<name>/template.toml`

Categories: `languages`, `tools`, `ides`, `databases`, `browsers`, `desktops`, `ai-tools`,
`education`. The loader scans the tree, so there is no index to update.

```toml
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

Params become `arg NAME=value` lines in the emitted Boothfile and are what `--select "buf:1.72.0"`
pins. Numbered segments (`"Boothfile--65"`) control ordering against other templates.

**A sibling `*--extension.toml` instead of a new template** when the thing is an add-on to an
existing entry — `templates/languages/go/` carries `linter--extension.toml`, `kernel--extension.toml`,
`vscode-ext--extension.toml`, `go-pkg--extension.toml`. Extensions may set `auto-select = true` and
`requires = ["notebook"]`. Selection syntax is `go/protobuf+go`. If your tool is "X support for
language Y", it is almost always an extension.

## 5. Test it

**Complex test** (does it actually install?) — `tests/complex/test-boothfile-<name>/`, auto-discovered
by directory name:

```
.booth/config.toml                    variant = "base"
.booth/Boothfile                      setup <name>
.booth/setups/<name>--setup.sh        ← copy of the script
test--boothfile-<name>.sh             sources ../../common--source.sh
```

**The copy under `.booth/setups/` is mandatory and is not redundant.** Tests run against the
*released* base image, which does not ship your new script yet; `setup <name>` resolves from
`.booth/setups/` first. Say so in a Boothfile comment, as
`tests/complex/test-boothfile-binary-companions/.booth/Boothfile` does. Keep the copy byte-identical.

The test body runs the tool and greps its output:

```bash
ACTUAL=$(run_coding_booth --silence-build -- <name> --version 2>/dev/null | head -1)
if echo "$ACTUAL" | grep -qE "<pattern>"; then
    print_test_result "true"  "$0" "1" "<name> is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "<name> should be installed"
    FAILED=$((FAILED + 1))
fi
```

**Config test** (does `booth config` emit the right lines?) — `tests/config/test<NN>-init-<name>.sh`
at the next free number (`ls tests/config | tail -3`), using `begin` / `run` / `assert-line` /
`finally` from `test-helpers--source.sh`. Assert the `setup`/`install` line and the version pin,
default and pinned:

```bash
run booth config $prj --no-tui --select "<name>:1.72.0"
assert-line "$prj/.booth/Boothfile" "arg <NAME>_VERSION=" '1.72.0' "<name> version pin"
```

**Run only what you touched** — the full suites are long:

```bash
tests/config/test<NN>-init-<name>.sh
(cd tests/complex/test-boothfile-<name> && ./test--boothfile-<name>.sh)   # needs Docker; builds an image
```

The complex test starts a real booth. Do not stop or remove containers you did not start, and clean
up the one you did.

## 6. Document it

- **`docs/CHANGELOG.md`** — required. New bullet at the top of `## Unreleased`, house style:
  bold lede sentence naming the feature, then what it unblocks and how to select it.
- **`docs/BOOTH_CONFIG.md`** — only if the tool joins an existing catalog table (e.g. the binary
  companions "library X → also select Y" list).
- **`docs/TODO.md`** — if this closes an open `- [ ]`, tick it in the same change.

`docs/AGENT_SETUP.md`'s "Common ones" list is a short illustrative sample, not a registry — leave
it alone unless the tool is genuinely a headline one.

## Done means

Script + template + both tests passing + CHANGELOG. Report what you ran and what you skipped —
"the complex test needs Docker and I did not run it" is a fine outcome to state, and not one to
paper over.
