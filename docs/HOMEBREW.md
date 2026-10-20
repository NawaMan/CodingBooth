# Installing CodingBooth via Homebrew — plan

> Status: **Phase 1 done** (wrapper 0.16.0, shipped in release 0.80.0). **Phase 2 done on Linux**
> (2026-10-20): `Formula/codingbooth.rb` in the tap points at the 0.80.0 `booth`; the Mac run
> (step 8) is still open. Phase 3 must land before the release after 0.80.0; Phase 4 at
> **v1.0.0**. User-facing install docs stay in [BOOTH_INSTALL.md](BOOTH_INSTALL.md) until then.

## Decision: package the wrapper, not the binary

The formula installs the `booth` **wrapper** as `booth` on `PATH` — the same file every release
already publishes at `releases/download/<version>/booth`. No Go build, no dependencies, one file for
every platform.

Homebrew takes over the job of the **global layer** (`curl … | bash` + `booth shell-config
install`). It does not touch the per-project layers:

| Layer | Today | With Homebrew |
| --- | --- | --- |
| Global | `install.sh` → central wrapper copy in the data dir + `booth()` in rc files | `brew install` → wrapper in the Cellar, symlinked onto `PATH` |
| Project | committed `./booth` + `.booth/tools/codingbooth.lock` pins the version | unchanged |
| Binary | shared cache `versions/<v>/`, sha256-verified | unchanged |

**Why not the Go binary.** Homebrew holds one global version; each project's lock pins its own. The
binary also picks image tags by its own version (`base-<version>`), so a brewed 0.80.0 binary
running a project pinned to 0.79.0 would quietly use 0.80.0 images. That breaks the reproducibility
promise. Making it work would need rustup-style shims that delegate to the pinned binary — a much
larger feature, not planned.

## What the trace showed (2026-10-07)

The wrapper was placed in a simulated Homebrew layout (`Cellar/codingbooth/<v>/bin/booth`,
symlinked from `prefix/bin/booth`), with a fake `HOME` and `BOOTH_CACHE_DIR`, and every command was
run through it:

| Where | Command | Result |
| --- | --- | --- |
| empty folder | `booth version` / `help` | ✅ works ("CodingBooth: not installed") |
| empty folder | `booth config --no-tui` | ⚠️ "not installed, run install" (expected without a TTY) |
| empty folder | `booth install` | ✅ copies `./booth` in, downloads + verifies the binary, writes the lock |
| **inside that project** | `booth list` / `booth --dryrun` / `booth version` | ❌ **"CodingBooth is not installed"** |
| **project subfolder** | `booth list` | ❌ same |
| inside the project | `./booth version` (control) | ✅ |

**Cause.** The wrapper resolves its own symlink and looks for `.booth/tools/codingbooth.lock`
**beside itself** (`booth`: `LOCK_FILE` derived from `WRAPPER_SELF`) — inside the Cellar. Finding
the project from `$PWD` is done only by the `booth()` shell function, and a formula cannot install
that: `post_install` is sandboxed and must not edit rc files in `$HOME`.

Running `booth shell-config install` from the brewed copy (into the fake `HOME`) made it work, which
confirms the shell function is the only missing piece. It also surfaced two more problems, below.

### Problem: `brew upgrade` would not reach the shell function's copy

`shell-config install` **copies** the wrapper to `~/.local/share/codingbooth/booth` (macOS:
`~/Library/Application Support/codingbooth/booth`), and the function calls that copy. A Homebrew user
who also ran `shell-config` would never get wrapper updates from `brew upgrade`.

### Problem: the `--code` bug (exists today, independent of Homebrew)

From a project **subfolder**, the `booth()` shell function appends `--code <project-root>` to every
command except `install|update|create` and `uninstall|version|help|shell-config`. That is right for a
run, but many subcommands do not define `--code`. Verified through the real shell function (0.79.0)
and against main's binary (0.80.0--rc1):

| From a subfolder | Result |
| --- | --- |
| `booth config` | ❌ `Error: unknown flag: --code` |
| `booth template list` | ❌ `Error: unknown flag: --code` |
| `booth list` | ❌ `flag provided but not defined: -code` |
| `booth expose list` | ❌ same |
| `booth message list` | ❌ same |
| `booth home-volume-list` | ❌ same |
| `stop` / `restart` / `remove` | ❌ same |
| run, `start`, `shell`, `exec`, `logs`, `build`, `emit-dockerfile` | ✅ these define `--code` |

From the project root nothing is appended, which is why it went unnoticed. Simply not appending is
wrong too: `config` from a subfolder must still target the project root, not `src/deep`.

The global-mode wrapper (step 2) ports this same dispatch logic, so the bug must be fixed with it,
not after.

## Steps

### Phase 1 — Make the wrapper Homebrew-ready ✅ done (wrapper 0.16.0)

Built in worktree `brew-ready`. The plan changed in one place: the environment-variable fix for the
`--code` bug was dropped. A new global wrapper hands off to each project's committed `./booth` and
pinned binary, which can be old; an old binary would ignore a new variable. Instead the wrapper
decides per subcommand, using only what every binary already understands:

1. **Global mode** (`GlobalDispatch` in `booth`). A wrapper with no lock beside it walks up from
   `$PWD` to the nearest `./booth` that is not itself and hands off. From a subfolder:
   - commands that take `--code` (run, `start`, `shell`, `exec`, `logs`, `build`,
     `emit-dockerfile`, `express`) get `--code <root>` **right after the subcommand**, so relative
     paths and a trailing `-- cmd` keep working;
   - commands with file-path arguments (`home-volume-export`/`-import`, `example`, `showcase`,
     `tools-cache`, `config <path>`) run unchanged from `$PWD`;
   - everything else runs from the project root, as if typed there.

   `install` / `update` / `create` stay about `$PWD`, and go to `$PWD/booth` when there is one — a
   foreign wrapper used to copy itself over it. `BOOTH_WRAPPER_HANDOFF` stops two lockless
   wrappers from exec'ing each other. Details: [implementations/WRAPPER.md](implementations/WRAPPER.md#global-mode).
2. **The `--code` bug is fixed** by the same table — the `booth()` shell function (bash/zsh and
   fish) is now a single call to the central wrapper, so there is one implementation, not three.
3. **Homebrew is recognised** by a real path containing `/Cellar/`: `shell-config install` declines,
   and `uninstall` outside a project refuses and points at `brew uninstall codingbooth`.
4. **Tests:** `tests/wrapper/033-global-mode-homebrew.sh` (Cellar layout, no rc files: install,
   root + subfolder hand-off in both modes, no overwrite of `./booth`, shell-config and uninstall
   refusals, no hand-off loop) and `034-shell-function-subfolder.sh` (the `--code` regression
   through the real function). Both fail against wrapper 0.15.3 for the bug they cover; the full
   wrapper suite passes.
5. **Docs:** [BOOTH_INSTALL.md](BOOTH_INSTALL.md) layer 1, [implementations/WRAPPER.md](implementations/WRAPPER.md),
   CHANGELOG Unreleased. The `README.md` install section waits for the tap (Phase 4) — there is
   nothing to `brew install` yet.

### Phase 2 — The tap (new repo `NawaMan/homebrew-tap`) ✅ Linux done (Mac open)

Needs 0.80.0 or later: every earlier release asset is the pre-0.16.0 wrapper, which has no global
mode. Publishing the tap before v1.0.0 is fine — nothing advertises it until Phase 4.

6. ✅ `Formula/codingbooth.rb` in `../homebrew-tap` (the clone of `NawaMan/homebrew-tap`):

   ```ruby
   class Codingbooth < Formula
     desc "Reproducible, containerized dev environments for any project"
     homepage "https://codingbooth.io"
     url "https://github.com/NawaMan/CodingBooth/releases/download/0.80.0/booth"
     sha256 "965458b7c132474692247e82bfe866c2e6e64a78b5b370cde528006963fa7644"
     license "Apache-2.0"

     # Not :github_latest: the repo also has a moving "latest" release.
     livecheck do
       url :stable
       strategy :github_releases
       regex(/^v?(\d+(?:\.\d+)+)$/i)
     end

     def install
       bin.install "booth"
     end

     def caveats
       <<~EOS
         CodingBooth needs Docker (Docker Desktop on macOS; rootful Docker Engine on Linux).
         Start a project with:  cd my-project && booth install
         Downloaded binaries live in the user cache; before `brew uninstall`, run
           booth uninstall --all-shared-binary   to remove them too.
       EOS
     end

     test do
       assert_match "CodingBooth Wrapper", shell_output("#{bin}/booth version")
     end
   end
   ```

   No `version` line: brew reads it from the URL path (`/download/0.80.0/`), and
   `brew audit --strict` rejects a stated one as redundant. The `test do` block works inside
   Homebrew's sandbox: `version` is handled before the wrapper's curl check and needs no network.
7. ✅ **Checked locally with Linuxbrew** (Homebrew 7.0.9, 2026-10-20). `brew tap nawaman/tap <local
   path>` clones the path, so it only sees **committed** files. `brew install`, `brew test`,
   `brew audit --strict --online`, `brew style` all pass; `brew livecheck` finds 0.80.0. The trace,
   with the Cellar wrapper by full path in a scratch `HOME`: `version` outside a project; `install`
   writes `./booth` (0.16.0) and a lock for binary 0.80.0; from a project subfolder `version`
   reports the project's binary, `config --no-tui --dryrun` works, and a run mounts the project
   root; `shell-config install` refuses and writes no rc file; `uninstall --wrapper -y` outside a
   project refuses and names `brew uninstall codingbooth`. Then `brew uninstall` and `brew untap`.
   (An installed `booth()` shell function hides the brew link — call it by path to test.)
8. **Run it once on a Mac** — Apple Silicon, with the system's bash 3.2. Check `install`, plus
   running inside a project and from a subfolder. (A grep of the wrapper found no bash-4-only
   features — `mapfile`, `declare -A`, `${x,,}` — but only a real run proves it.)

### Phase 3 — Release automation (this repo)

Lands after Phase 2 (the step edits a formula that must already exist) and before the release
after 0.80.0, so that release bumps the formula on its own.

9. **Token:** a fine-grained token with write access to `homebrew-tap` only, stored as a repo
   secret (e.g. `HOMEBREW_TAP_TOKEN`).
10. **Workflow step** in `.github/workflows/release-binary-and-wrapper.yaml`, after the versioned
    publish: take the sha256 of `booth`, update `url` and `sha256` in the formula (the version
    comes from the URL), and commit straight to the tap (own repo — no PR needed;
    `brew bump-formula-pr` or a short `sed` script both work). Stable releases only — the existing `--rc` guard already ensures that. The
    formula must always use versioned URLs, never the moving `latest` tag.
11. **Which version the formula follows:** the **release** version (1.0.0, 1.1.0, …), not the
    wrapper's own `VERSION=` (0.15.x). No new tagging needed; the cost is that `brew upgrade`
    sometimes reinstalls an unchanged wrapper, which is harmless.

### Phase 4 — Launch with v1.0.0

12. Add `brew install nawaman/tap/codingbooth` to `README.md`, the site, and
    [BOOTH_INSTALL.md](BOOTH_INSTALL.md), next to `curl … | bash`. Keep `install.sh` — Linux users
    without Homebrew and Windows users still need it.
13. **Later, optional:** submit to homebrew-core once the project meets its notability bar. Expect
    pushback: the wrapper downloads binaries at runtime, which homebrew-core discourages.

## Not a problem

- **Gatekeeper:** formula downloads are not quarantined, and the darwin binary is still fetched by
  the wrapper as today. Use a formula, not a cask — casks are quarantined.
- **Linuxbrew:** the same formula works.
- **Wrapper copies in projects:** `install` copies the wrapper into each project as an independent
  file, so Cellar paths changing on `brew upgrade` do not affect them.

## Why now vs v1.0.0

The wrapper changes (Phase 1) define how `booth` finds a project — shell function, global wrapper,
or both. That is part of the install contract v1.0.0 should freeze, so it lands before the tag (it
ships in 0.80.0). The tap and release automation (Phases 2–3) follow 0.80.0 so the formula can be
tested against a real release and bumps itself from then on; only the announcement (Phase 4) waits
for v1.0.0.
