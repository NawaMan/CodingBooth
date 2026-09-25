# Modern UX for Desktop Variants — Omarchy-Inspired Suggestions

[Omarchy](https://omarchy.org/) is DHH's opinionated Arch Linux + Hyprland distro. A 2026-09-22
review of what people specifically like about it was checked against `variants/desktop-{xfce,kde,lxqt,wayland}/`
to see what, if anything, is worth borrowing. This doc records the findings and the suggestions —
not a committed plan, just what's worth doing next and why.

**Approach: no parity goal.** The point isn't to make Booth look or act like Omarchy — it's a
source of ideas, not a target. Each suggestion below is tried as its own independent, low-stakes
experiment: implement it, see if it actually earns its place, keep it if so, drop it without
ceremony if not. Adopting one item implies nothing about the others.

## Already covered — no action needed

Several of Omarchy's most-liked pieces already have an equal or stronger equivalent here, opt-in via
templates rather than baked into the default image:

- **AI agent CLIs pre-wired** — `templates/ai-tools/` (claude-code, codex, gemini-cli, gh-copilot,
  opencode, cursor, aider, goose, grok, warp, ollama, anythingllm, antigravity, herdr, oh-my-pi) is
  broader than Omarchy's own bundle of ten.
- **Editor choice** — `templates/tools/neovim` exists alongside the VS Code default.
- **Curated app bundle** — `templates/desktops/` (Firefox, Chrome, Chromium, GIMP, Inkscape,
  LibreOffice) and `templates/tools/obsidian`.
- **Fast, minimal Wayland compositor** — `desktop-wayland` deliberately uses **labwc**, not Hyprland:
  labwc's wlroots headless backend needs no logind/seat/GPU, which is exactly what a container needs.
  Hyprland assumes real DRM output and would be a regression here, not an upgrade.
- **Modern terminal on Wayland** — `desktop-wayland` already installs **foot** as its terminal.

The gap isn't tooling *availability*, it's that the X11 desktop variants (`desktop-xfce`,
`desktop-kde`, `desktop-lxqt`) still only offer each DE's stock terminal, and none of the four
desktop variants let you change wallpaper/theme after build time.

## Suggested additions

### 1. Modern GPU-terminal option for the X11 desktops (Alacritty / Kitty)

**Status: shipped (2026-09-23).** `variants/base/setups/alacritty--setup.sh` and
`kitty--setup.sh`, selectable via `templates/desktops/alacritty` and `templates/desktops/kitty`
(`--select alacritty` / `--select kitty`). Each seeds `FiraCode Nerd Font Mono` on first
container start via a `57-cb-<name>--startup.sh` startup hook (idempotent — never overwrites a
hand-edited config), and registers a desktop icon via `cb-desktop-icon.sh` — the same generic
mechanism Firefox/GIMP/Inkscape already use, which was missing from the first pass (caught by
review: "without a launcher, people won't know" — fair). Proven end-to-end, not just installed:
`tests/complex/test-boothfile-alacritty` and `test-boothfile-kitty` start a throwaway `Xvnc`
session, have each terminal run a command in its pty (checked via a marker file — a terminal
renders its child in its own window, not the caller's stdout, so that's the only reliable signal),
and check the icon lands in `/etc/skel/Desktop`. `examples/workspaces/desktop-terminals-example`
does the pty/marker-file proof against a real running desktop booth via `docker exec`. All four
catalog guards (`test86`/`test88`/`test90`/`test92`) pass. Not verified on arm64 — flagged, not
blocking. Kitty comes from a pinned, SHA256-verified upstream release rather than apt (2026-09-24):
noble's `kitty` 0.32.2 gets security fixes only through Ubuntu Pro, and is open to
CVE-2026-72913, where displaying untrusted output can run commands.

**2026-09-23 addendum — `+default` extension.** Both were originally *alternate* terminals only
— no way to make either the one that actually opens when the desktop says "open a terminal."
`templates/desktops/{alacritty,kitty}/default--extension.toml` (`--select
xfce/alacritty+default`, any of the four desktop variants) closes that gap via a new
`default-terminal--setup.sh`, which writes whichever DE-specific "default terminal" setting is
present — XFCE's `helpers.rc`, KDE's `kdeglobals` plus moving Konsole's Ctrl+Alt+T in
`kglobalshortcutsrc`, and on LXQt PCManFM-Qt's `[System] Terminal=` plus a Ctrl+Alt+T binding — at
container start, no-clobber like the font seeding. labwc (Wayland) has no such registry at all; the
terminal was hardcoded (autostart and right-click menu) inside `wayland--setup.sh`'s
runtime-generated `start-wayland` script, now read from `/opt/codingbooth/default-terminal`
(falling back to `foot`), which also drives a generated `rc.xml` rebinding labwc's Super+Enter.
`x-terminal-emulator` is pinned to the chosen terminal on every desktop. Proven per-desktop in
`tests/complex/test-boothfile-default-terminal-{xfce,kde,lxqt,wayland}`, including that a
hand-edited registry file is never clobbered on a later container start.

<details>
<summary>Original feasibility check (2026-09-22, before implementation)</summary>

`desktop-wayland` has foot; `desktop-xfce`/`desktop-kde`/`desktop-lxqt` have no equivalent — only
each DE's stock terminal (xfce4-terminal, Konsole, qterminal). The risk was that Alacritty/Kitty are
GPU-accelerated (OpenGL) terminals and TigerVNC's `Xvnc` might not expose a working GL context.
Tested directly against a running `nawaman/codingbooth:desktop-xfce-0.78.0` container (throwaway,
torn down after):

- `glxinfo -B` under `Xvnc` reports **`direct rendering: Yes`**, renderer **Mesa llvmpipe, OpenGL 4.5
  core profile** — software-rendered, but a real, working GL context.
- `alacritty` (0.13.2) and `kitty` (0.32.2) are both in Ubuntu 24.04's `universe` repo — **no PPA
  needed**, same `apt-get install` flow as every other setup script.
- Both launched cleanly against the live `:1` display (`alacritty -e sh -c 'echo hello'`, same for
  kitty) — **exit 0, no GL/X errors**.

**Scope:** add as an opt-in *alternate* terminal per X11 desktop variant (same relationship neovim
has to VS Code) — not a replacement for xfce4-terminal/Konsole/qterminal, which stay default.

**Effort:** small — one setup script per terminal, following the existing `<de>-wallpaper--setup.sh`
pattern (install package, seed a default config file, done).

</details>

### 2. Theme-switcher across the X11 desktop variants

**Status: feasible, no technical blocker — bigger in scope than #1.**

Right now each desktop variant hardcodes one wallpaper + one Nerd Font at build time, with no way to
change it afterward. Omarchy's most-photographed feature is instant, system-wide theme switching.
The mechanism to do this already exists in this repo, just single-purpose (wallpaper only) — the
same tools would extend to full theme bundles:

| DE | Wallpaper today (already shipped) | Theme extension (same tool) |
|---|---|---|
| XFCE | `xfconf-query` on the `xfce4-desktop` channel (`xfce-wallpaper--setup.sh`) | `xfconf-query` on the `xsettings` channel (`/Net/ThemeName`, `/Net/IconThemeName`) + a palette block in `xfce4-terminal`'s `terminalrc` (which already gets a seeded `FontName=` line) |
| KDE | `plasma-apply-wallpaperimage` (`kde-wallpaper--setup.sh`) | `plasma-apply-colorscheme` — Plasma's own sibling CLI for exactly this |
| LXQt | `pcmanfm-qt --set-wallpaper` (`lxqt-wallpaper--setup.sh`) | `qt5ct`/`qt6ct` config + an Openbox theme swap |

**Scope suggestion:** start with 2–3 curated bundles (wallpaper + GTK/Qt theme + terminal palette),
not Omarchy's 20+ — keeps image size and maintenance sane for a first pass.

**Effort:** medium — three apply-paths (one per DE, each DE's own tool), plus actually curating the
theme bundles themselves.

### 3. (Optional, deferred) Default-bundle an AI agent CLI in desktop images

**Status: not a technical question — a scope/tradeoff decision, not evaluated for feasibility.**

Bake one agent CLI (e.g. `claude-code`) into the desktop variant images by default, instead of
leaving all of them opt-in via `templates/ai-tools/`. This is the closest one-to-one match to
Omarchy's "agentic OS" pitch. Tradeoff is image size vs. out-of-the-box feel — CodingBooth's
opt-in model already covers more agents than Omarchy ships, so this is purely about *defaults*,
not availability. Left as a separate decision; no further work done on it here.

## Not recommended

- **Swapping `desktop-wayland`'s labwc for Hyprland** — labwc was deliberately chosen for headless
  container compatibility; Hyprland needs real DRM output.
- **Gaming stack (Steam/Proton/RetroArch)** — off-mission for a dev booth image, pure bloat.
- **Mise-style unified runtime manager** — `templates/languages/*` already covers per-language
  version pins in a more Docker-native, composable way (`--select go+python+node` vs. a wrapper).

## Evaluation log

- **2026-09-22** — GLX/OpenGL confirmed working under `Xvnc` via Mesa llvmpipe software rendering
  (`glxinfo -B`: `direct rendering: Yes`, OpenGL 4.5 core). Alacritty 0.13.2 and Kitty 0.32.2 both
  installed from Ubuntu 24.04 `universe` (no PPA) and launched cleanly against a live `:1` Xvnc
  session inside `nawaman/codingbooth:desktop-xfce-0.78.0`, no GL/X errors. Verified in a throwaway
  container (`cb-eval-glx`), removed after.
- **2026-09-23** — Item #1 implemented on branch `modern-ux-terminals`. Found along the way:
  `docker exec` defaults to root, whose `$HOME` has no `.Xauthority`, so launching either terminal
  that way fails with `Authorization required, but no authorization protocol specified` — must
  exec as `coder`. TigerVNC's actual process name is `Xtigervnc`, not `Xvnc` (a readiness-poll
  gotcha). Neither terminal forwards its child command's exit code or stdout — both render the
  child in their own pty/window — so proving "it ran" needs the child to write a marker file, not
  a captured-output or exit-code check.
- **2026-09-23 (user report)** — user tried `herdr` (the agent multiplexer, `templates/ai-tools/herdr`)
  inside Alacritty and got a garbled pane: the raw PS1 template text
  (`\[\e[1;32m\]desktop-terminals-example\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]$`) printed literally,
  repeated with `^C` after each line. Investigated: **confirmed** `TERM=alacritty` had no matching
  terminfo entry in the image (Ubuntu's `alacritty` apt package ships none, unlike `kitty`, which
  gets `xterm-kitty` automatically via the `kitty-terminfo` dependency) — fixed by adding
  `ncurses-term` to `alacritty--setup.sh`. **Not fully confirmed** that this is the complete
  explanation: `\w` appeared unexpanded, not just uncolored, which bash expands regardless of
  terminal capability — suggests the shell inside herdr's pane may not be processing PS1 as an
  interactive bash prompt at all (a herdr-side behavior, out of this repo's scope, not verifiable
  without a live interactive session). User should retry after the terminfo fix and report back
  whether it's resolved or narrowed.
- **2026-09-23 (resolved — not this repo's bug)** — user retried after the `ncurses-term` fix:
  still garbled, and confirmed the **same garbling in the default xfce4-terminal**, not just
  Alacritty/Kitty — ruling out anything in this repo. A second screenshot showed the actual cause:
  `\e]133;k;start_kitty\a` OSC-133 markers (kitty's bash shell-integration snippet) followed by
  `/bin/sh: 1: T: not found` — herdr is spawning `/bin/sh` (dash) for its panes rather than the
  user's real shell, and dash chokes on bash/kitty-specific shell-integration text, trying to
  execute fragments of it as commands. This is a herdr bug, unrelated to the alacritty/kitty work
  above. Stopped investigating further per user's call.
- **2026-09-23 (`+default`, LXQt)** — first cut wrote `lxqt.conf`'s `[General] terminal=` and its
  test passed, because the test only read that file back. Tried live: desktop right-click →
  "Open in Terminal" failed with `Failed to execute child process "xterm"`. Nothing in
  lxqt-session / lxqt-config-session / liblxqt reads that key; PCManFM-Qt uses its own
  `[System] Terminal=` (compiled-in fallback `xterm`, not installed). It reads the user
  `settings.conf` *or* the `/etc/xdg` copy, not a merge — so the seed copies the system file first
  to keep the wallpaper — and it saves every setting (including `Terminal=xterm`) back on exit,
  so editing the file while it runs is lost. Also found: Ubuntu installs LXQt's default shortcuts
  at `/etc/xdg/lxqt/globalkeyshortcuts.conf/globalkeyshortcuts.conf` (a directory), so
  Ctrl+Alt+T was unbound entirely; now bound in the user file. Both proven on a running desktop:
  an xdotool Ctrl+Alt+T spawned alacritty. Lesson: for a "default app" setting, a config-file
  check proves nothing unless something is known to read that file.
- **2026-09-23 (`+default`, KDE Ctrl+Alt+T)** — `TerminalApplication` doesn't cover the shortcut:
  Ctrl+Alt+T is Konsole's own kglobalaccel launch action (`X-KDE-Shortcuts` in
  `org.kde.konsole.desktop`). Plasma 5.27 / kglobalaccel 5.115 keeps it as
  `[org.kde.konsole.desktop] _launch=<current>,<default>,<name>`; setting Konsole's current to
  `none` and adding `[kitty.desktop] _launch=Ctrl+Alt+T,none,kitty` works, and kglobalaccel
  keeps both when the file is seeded before the session's first start. Proven with a real
  keypress on a fresh booth (kitty spawned, konsole didn't). One false alarm on the way: the very
  first xdotool key sent into a just-started session was dropped; a second press, or a throwaway
  key first, behaves normally — a harness artifact, not the feature.
- **2026-09-23 (`+default`, Wayland)** — first cut passed the choice to `start-wayland` as a
  `DEFAULT_TERMINAL` export in `/etc/profile.d`, and its test passed because the test launched
  `start-wayland` from a login shell. On a real booth it came up with foot: booth-entry starts
  the desktop with `exec runuser -u coder -- start-wayland-wrapped` — no login shell, so
  profile.d is never sourced (the process env had only `HOME` and `NOVNC_PORT`). Now a file,
  `/opt/codingbooth/default-terminal`, read by `start-wayland` itself. The test launches it with
  `env -i` to match; it failed first against the old code, then passed. Same lesson as LXQt, in
  a different form: the test's launch path must be the product's launch path.
- **2026-09-23 (`+default`, Wayland keys)** — a foot window opened from Apps (wofi) was expected:
  the Wayland image always installs foot. Two real gaps found checking it: `x-terminal-emulator`
  was still foot (kitty registers as an alternative, but at lower priority), and labwc 0.7.1's
  built-in Super+Enter is hardcoded to `alacritty`. Fixed both; proven with `wtype` key events on
  the live session — Super+Enter spawned kitty, and Alt+F4 still closed a window, so `<default />`
  kept labwc's other bindings while the later `W-Return` overrode the built-in one.
