# Changelog

This file contains a list of changes for each released version.

## Unreleased

- **Penpot is a Tools catalog template (experimental).** `--select penpot` copies the
  official `penpotapp/backend` and `penpotapp/frontend` images into the
  booth (CloudBeaver-style `copy --from`, no Docker-in-Docker) and pulls
  in PostgreSQL and Redis. The design UI does not start or publish a port
  on its own — add `+autostart` to run it on boot and `+expose` to reach
  it from the host. First browser visit creates the account (email
  verification is off). Pin the image tag with `penpot:2.17.2`. Optional
  `+exporter` copies `penpotapp/exporter` (Playwright/Chromium, ~650MB)
  so File → Export works. Default port 19001. Tests:
  `test107-init-penpot.sh`.

- **The base variant console can now save its layout and Web view tabs back to `.booth/console.json`
  itself, via a new `--console-spec <shared|cache>` flag / `console-spec` config key, instead of
  only ever reading it.** `shared` saves to the same committable `.booth/console.json` described
  above, but needs `--writable-booth` since `.booth/` is otherwise bind-mounted read-only — without
  it a save fails cleanly (logged, not fatal) and the change still lives on in that browser's
  `localStorage`. `cache` saves to `.booth/.tmp/console.json` instead, which is always writable
  regardless of `--writable-booth` (the same always-read-write mount already used for session/idle/
  lifecycle state) but is never git-committed, for a "remember for my next session" without
  affecting teammates. Leaving it unset keeps today's read-only behavior exactly as before. Wired
  end-to-end: a new `AppConfig.ConsoleSpec` field (auto-picked-up by `ConfigKeys()`'s reflection, no
  extra work needed there), a CLI flag parsed the same way as the adjacent `--count-down-exit-code`,
  a `BOOTH_CONSOLE_SPEC` env var exported before `booth-message-api-server` starts (it forks a fresh
  handler per connection off its own environment snapshot, so anything exported after it starts
  would've been invisible to it — caught before it caused a live bug), a new
  `/booth-messages/api/console-config` POST route in that same Bash server that validates the body
  is a JSON object and writes it atomically (temp file + `mv`), and a debounced save from the
  front-end whenever layout or tabs change, suppressed until the page's own initial-load hydration
  finishes so a fresh load never immediately re-saves exactly what it just read. Locked in with a
  new dryrun test (CLI flag, config.toml key, and absence all produce/omit the right env var) plus
  the existing full suite. One accepted limitation, by design: `index.html` is rendered once at
  container boot and served static for the container's whole life, so a save updates the file on
  disk immediately but a currently-running container won't reflect it until restarted — matches the
  read-only file's own load-once behavior, and isn't worth an async-boot rework to avoid. See
  `docs/BOOTH_CONSOLE.md`.

- **Fixed a pane staying on its Web view tab, visually, after switching back to Terminal** — the
  header correctly reverted to "Session N", but the tab's content stayed stacked on top of the now-
  visible terminal underneath. `switchToTerminal` cleared the pane's `has-active-tab` class (which
  un-hides the terminal) but never cleared the web-tab iframe's own `is-active` class, a separate
  CSS rule keyed off the iframe itself that independently kept it `display: block`. Fixed by
  explicitly deactivating the active web-tab-frame there too; `activateTab` already recomputes
  `is-active` correctly the moment Web view is reopened, so nothing about the tab is lost — verified
  the full round trip (open a tab, back to terminal, back to the tab) live.

- **A project can now check in the base variant console's starting split layout and pre-opened Web
  view tabs, via `.booth/console.json`.** Layout name plus an arbitrary, per-pane list of tab
  addresses is genuinely structured data — not a string, bool, or flat list — so it doesn't fit
  `config.toml`'s scalar/list schema without real CLI changes. Rides the same mechanism
  `.booth/cache/` and `.booth/shared/` already use instead: `.booth/` is bind-mounted read-only into
  every booth already, so `start-ttyd-split` just reads the file directly at container start — no
  `docker -e`, no environment variable, no CLI changes at all. Validated as JSON via `jq` (already
  in the base image); a malformed file is logged and ignored rather than breaking the console, and
  is embedded into the page as inert `type="application/json"` text rather than a raw object
  literal, so even a validation gap can't take the page's own script down with a syntax error.
  Every tab address is parsed by the exact same parser the address bar itself uses, so anything that
  works typed in works here too (`:3000`, `myserver:9000`, `https://example.com`, ...). Strictly a
  *first-visit default*: the moment a pane is customized in a given browser (opened, a tab closed,
  whatever), that sticks in `localStorage` and wins over the file on every later load — editing the
  file doesn't retroactively change an already-customized console. See `docs/BOOTH_CONSOLE.md`.

- **Web view toolbar polish: Back/Forward now only appear where they can actually work, the "+" new-
  tab button moved to the left of the tab strip, the Markdown-view icon moved next to the
  Terminal/Web toggle, and Ctrl/Cmd-click on a link inside a booth-proxied tab now navigates that
  tab instead of opening a new browser tab.** Back/Forward were silently broken for every external
  tab — reading `.history` at all on a genuinely cross-origin iframe throws a `SecurityError`
  outright, not just "no history to go back to" — so they're now hidden entirely for those tabs
  instead of sitting there looking clickable and doing nothing; a booth (proxied, same-origin) tab's
  history is real and unaffected, buttons stay exactly as before. (A parent-tracked, address-bar-
  only history was tried and removed for external tabs: it can't see a link clicked *inside* a
  cross-origin page, which is how people actually browse one, so it stayed disabled for the common
  case anyway — not worth the complexity for what it bought.) The rewriting-caveat warning icon is
  booth-only for the same reason and moves with them. Ctrl/Cmd-click interception works the same
  way `applyIframeFallbackStyle` already does — injecting into the frame's own document — so it's
  also booth-only; a cross-origin tab's document is as unreachable as its history object.

- **A Web view tab's address bar now also accepts a bare `host:port` with no dot, and falls back to
  a Google search for anything that isn't a URL or recognizable host at all**, matching a real
  browser's omnibox. `myserver:3000` (no scheme, no dot — an internal/LAN-style name) resolves the
  same as any other external host; a bare single-label word with no port is still too ambiguous
  with a plain typo to treat as a host, so it — and anything else with no URL or host shape —
  becomes a query against `https://www.google.com/search?q=…&igu=1` instead of erroring. `igu=1` is
  Google's own undocumented flag that lets its results page be framed at all (it refuses by
  default, same as most sites); verified live, real results render inside the tab. The tab chip
  shows `Search: <query>`; the address bar shows the typed text itself, not the constructed URL.
  Needed storing a tab's resolved `src` explicitly rather than always re-deriving it (from
  port/path for a booth tab, or reusing `display` for a plain external one): a search tab's
  `display` is the raw typed text, not a URL, so it can't be recomputed from that on a reload —
  falls back to the old reconstruction for a tab saved before `src` was persisted.

- **A console pane's Web view tab now accepts any URL, not just a booth port.** Only host `booth`
  still routes through the `/proxy/{port}/` rewrite (and only over `http` — the proxy has no TLS);
  every other host, including `localhost`/`127.0.0.1`, now opens directly in the tab's iframe with
  no rewrite at all. `localhost`/`127.0.0.1` changed meaning as part of this: they used to be
  treated as this booth (a paste-friendly alias, since a dev server prints `http://localhost:3000`
  but means "this container"), and now mean the machine actually running the browser, same as
  typing them into any other address bar — so `https://localhost:...` also works now, since the
  restriction to `http` was specifically about the booth proxy's lack of TLS, not about localhost.
  A bare host with no scheme (`example.com`, `example.com/path`) assumes `https`; any scheme other
  than `http`/`https` (`javascript:`, `data:`, `ftp:`, ...) is refused outright, since the address
  becomes an iframe `src`. Fixed three places that used a tab's booth `port` as its "has this tab
  loaded anything" signal — an external tab legitimately has no port at all, so each was reading a
  fully-loaded external tab as still-empty: the has-content/warning-icon check, the Escape-cancels-
  a-blank-tab check, and reload persistence's stale-tab filter. All three now key off the tab's
  `display` instead, which is set for both booth and external tabs alike.

- **Each console pane's Web view can now hold more than one tab.** Previously a pane's Web view was
  a single target — typing a new address replaced whatever was open. The globe button's Web view
  now carries its own tab strip: any number of tabs, each with its own independently-mounted
  iframe, so switching between them is a visibility toggle, not a reload — a background tab keeps
  its scroll position, form state, and websockets. Tabs (and which one is active) persist in
  `localStorage` per pane and survive both a Terminal↔Web view toggle and a full page reload,
  restoring every previously-open tab's iframe. Opening Web view with no tabs yet, or closing the
  last one, leaves the terminal visible underneath rather than a blank pane. Fixed three real bugs
  surfaced while building this: a freshly-opened tab briefly showed the terminal through it instead
  of a blank page (the terminal was only hidden once the active tab had real content, not just an
  active tab); the address bar's blur handler unconditionally reset the field to the active tab's
  saved address, so clicking a fresh tab's own empty body — which blurs the input — wiped whatever
  was typed or prefilled, since a brand-new tab has no saved address to fall back to; and
  `flashAddrError`'s reserved-port rejection cleared the typed value and never restored it (only
  the placeholder came back), unlike the https-URL rejection, which already left the text alone.

- **Narrowed the ttyd Nerd Font race further: a pane's font now has to finish loading before its
  iframe even starts navigating**, not just before the fallback-then-swap flash gets corrected
  after the fact. The console shell itself — which renders before any pane's ttyd backend is even
  ready — now preloads and registers the same `@font-face` the pane's own `sub_filter` injects, and
  gates a pane's first navigation (and a Terminal↔Web view round trip) on `document.fonts.load()`
  resolving, capped at 2s so a stalled font can never block the terminal from appearing. By the
  time a pane's iframe is allowed to navigate, the font is normally already decoded and
  cache-resident, so the existing detect-and-`resize` correction rarely has anything left to
  correct. Caught a real bug in the first pass: the gate initially had no matching `@font-face`
  declared in the shell's own document, so `document.fonts.load()` had nothing to wait on and
  resolved immediately regardless of whether the font was actually ready.

- **A console pane's shell now survives a page reload instead of dying with the websocket.** ttyd
  spawns a fresh process for every connection, so a bare `bash -l` (in `start-ttyd-split`, and the
  `start-ttyd` fallback used when `BOOTH_WEB_SPLIT=false`) was killed outright the moment a reload
  or a dropped connection SIGHUPed it — taking down any foreground job, a dev server or a build,
  along with it — and reconnecting handed back an empty shell with no memory of what was running.
  Each pane's shell now lives inside `tmux new-session -A -s <pane>` instead: the tmux server holds
  the session independently of any one client, and `-A` reattaches an incoming connection to the
  existing session rather than replacing it, so a reload resumes exactly where it left off,
  scrollback included. tmux was already in the base image. Verified live: started a counting loop
  in a pane, hard-refreshed, and watched it resume mid-count rather than restart.

- **Fixed extra letter-spacing in the ttyd Nerd Font terminal that only went away after a hard
  refresh.** ttyd's bundled xterm.js measures its terminal cell width once, synchronously, against
  whatever font is actually rendering at that instant — usually the browser's fallback monospace,
  since the Nerd Font `@font-face` is still loading — and never re-measures once the real font
  swaps in. Every cell stayed sized for the fallback's wider advance width while the narrower Nerd
  Font glyphs rendered inside it, producing a visible gap between every character; a hard refresh
  only "fixed" it by the accident of the font already being cached by the time xterm measured.
  Both places that splice the Nerd Font in — `web-ttyd-split/nginx.conf.template`'s per-pane
  `sub_filter` and `ttyd-nerd-font-index--setup.sh`'s baked `index.html` (used when
  `BOOTH_WEB_SPLIT=false`) — now also inject a small script that detects the mismatch and corrects
  it. Getting there took three tries: calling xterm's own `_charSizeService.measure()` directly
  (once as a single attempt after `document.fonts.ready`, once debounced on xterm's `onRender`
  going quiet) corrupted the terminal — blank rows, or a stuck resize — whenever it landed while a
  reattached tmux pane was replaying its buffer, reproduced live. A JS-triggered `location.reload()`
  was tried next, on the theory that a manual hard refresh always fixes this; it doesn't reliably —
  the reloaded page can lose the same race again, with no way to retry in place. The fix that
  actually holds up: independently measure the loaded font with a throwaway canvas context (zero
  side effects), compare it to xterm's cached cell width, and when they disagree, dispatch a plain
  `resize` event — which drives ttyd's own window-resize handler, the same code path every browser
  window resize already exercises, rather than reaching into xterm's internals directly. Verified
  clean across repeated reattaches to the same live session (the scenario that broke both earlier
  attempts) with no reload and no rendering corruption.

- **Nerd Fonts served to the browser are now WOFF2, not the raw `.ttf`, cutting the transfer by
  roughly half.** `FiraCode Nerd Font Mono` is ~2.7MB per weight as a `.ttf` — mostly the thousands
  of icon glyphs Nerd Fonts patches into every font it ships, not the base typeface — and every
  extra millisecond spent fetching or decoding it widens the race the fix above corrects for.
  `fira-code-nerd-font--setup.sh` now also runs `woff2_compress` on the two weights the web terminal
  actually serves (Regular/Bold Mono), producing a `.woff2` sibling at roughly half the bytes
  (~1.2MB) alongside the `.ttf` it still installs for fontconfig/native apps. Every place that
  serves the font to a browser — `web-ttyd-split/nginx.conf.template`'s per-pane `sub_filter`,
  `ttyd-nerd-font-index--setup.sh`'s embedded data URI, and the codeserver/notebook wrapper's
  `WRAPPER_HEAD_INJECT` (`booth-message-codeserver-wrapped--setup.sh`,
  `booth-message-notebook-wrapped--setup.sh`) — now references the `.woff2` instead, and the three
  nginx-served paths also get a `<link rel="preload">` so the fetch starts the instant the
  document's `<head>` is parsed rather than waiting for CSS to discover it's needed. This narrows
  the race window; it doesn't close it — decoding a font is always asynchronous, however fast it's
  fetched — so the detect-and-`resize` fix above still does the actual correcting.

- **`shell` / `exec` accept `--code <path>` to target (or, with `--run`, create) a booth by the
  code path it was created from, instead of by name.** Alone, `--code` cascades the same way
  `--run` does for names: a running booth on that path is used as-is, a stopped one is started
  with `--run`, and a missing one is created there with `--run` (rooted at `--code` instead of the
  current directory). Combined with `--name` / a positional name, `--code` is not a narrowing
  search — one code directory can back any number of differently named booths — it's an identity
  check: if the named booth's own code path disagrees, the command refuses with a hard,
  unconditional error naming both paths. Unlike a `--port` create-flag mismatch, this is **not**
  affected by `--accept-existing` — a wrong code path means `--name` resolved to the wrong
  project, and there is no "connect anyway" for that. Unit tests cover the resolution cascade and
  the mismatch rules; complex test `tests/complex/test-connect-code-path/` exercises target-by-code,
  start-stopped, create-new-rooted-there, matching name+code, and the unconditional mismatch
  refusal (with and without `--accept-existing`). See `docs/BOOTH_CONNECT.md`.

- **Added five more database GUI/TUI clients as selectable templates:
  `lazysql`, `dblab`, `harlequin`, `sql-studio`, and `heidisql`.** All are
  opt-in only (`booth config --select <name>`), none baked into the base
  image. `lazysql` (jorgerojas26/lazysql) and `dblab` (danvergara/dblab) are
  Go TUI clients for MySQL/PostgreSQL/SQLite3/SQL Server; `dblab` is unusual
  among these tools in taking real `--host`/`--port`/`--user`/`--driver`
  connection flags directly, rather than only prompting interactively.
  `harlequin` (tconbeer/harlequin) is a Python SQL IDE installed into an
  isolated venv at `/opt/harlequin` (same pattern as `aider`); its own
  install covers SQLite and DuckDB, with Postgres/MySQL needing a separate
  adapter package noted in its summary, and it ships `hsql`, a
  non-interactive "run this SQL and exit" companion useful in scripts. Each
  of the four's setup script documents CodingBooth's own convention —
  `postgresql`/`mysql` grant the container user a passwordless local
  superuser role but create no database matching that user's name, so a
  connection needs to name one that actually exists (PostgreSQL's is always
  `postgres`).
  `sql-studio` (frectonz/sql-studio) is different in kind: a single Rust
  binary that serves a browser-based SQL explorer (SQLite, libSQL, Postgres,
  MySQL, DuckDB, ClickHouse, SQL Server, Parquet/CSV) rather than a
  terminal UI, so it gets the full `cloudbeaver`-style treatment — a `PORT`
  param, a `start-sql-studio` launcher, and a desktop icon (via
  `cb-web-icon.sh`). With no target on the command line (the icon's first
  click, or running `start-sql-studio` bare in a desktop session), it now
  asks via a `zenity` dialog what to open — a SQLite/DuckDB/CSV file
  (`zenity --file-selection`) or a Postgres/MySQL URL (pre-filled with
  CodingBooth's own-user/no-password/localhost convention) — falling back
  to sql-studio's own `sqlite preview` sample if zenity isn't installed
  (headless/`base` variant) or the dialog is cancelled. A caller-supplied
  path is passed straight through untouched — a fix along the way: the
  launcher used to unconditionally `cd` into its own state directory
  before running, which silently broke any relative path given to it.
  `heidisql` is HeidiSQL's native Linux build (still beta upstream),
  amd64-only like `dbeaver` (arm64 only has an unpackaged beta tarball,
  declared as `unsupported-arch` with a note pointing at `dbeaver`/
  `cloudbeaver` instead); its `.deb` also needs `libqt6pas6`, a dependency
  Ubuntu itself does not package, installed first from a separate release
  per HeidiSQL's own documented workaround
  (github.com/HeidiSQL/HeidiSQL/issues/2427). Tests:
  `tests/complex/test-boothfile-{lazysql,dblab,harlequin,sql-studio,heidisql}/`
  — each proves the tool does something real (a live query against a
  PostgreSQL server also installed in the test booth, an `hsql` query, an
  HTTP response, or a genuine `dpkg`-verified install), not just that a
  binary landed on `PATH`.

- **Added `sqluv`, a terminal UI SQL client, as a selectable tool template.**
  `sqluv` (github.com/nao1215/sqluv) queries MySQL, PostgreSQL, SQLite3, and
  SQL Server, plus local/HTTPS/S3 CSV/TSV/LTSV files, all through one TUI;
  connections are entered interactively and it remembers them for later
  launches. Unlike `lazygit`, it isn't baked into every booth by default —
  select it with `booth config --select sqluv` (or pin a version with
  `sqluv:0.4.8`). It has no CLI flags or documented config format for
  supplying a connection up front (its saved-connection store is internal
  and encrypts passwords), so this doesn't try to auto-wire it to any
  database also running in the booth; the setup script's closing summary
  just documents the convention CodingBooth's own `postgresql`/`mysql`
  setups already share — host `localhost`, user matching the container
  user, no password, default port — as a hint for the interactive prompt.
  Tests: `tests/complex/test-boothfile-sqluv/`.

- **The notebook variant's JupyterLab now renders the Fira Code Nerd Font
  too, in both its terminal and its file/notebook editors.** JupyterLab is
  wrapped by the same shared nginx layer as code-server, but its real UI
  lives at `/lab` (and nested paths under it), not the bare root — so this
  needed the shared wrapper's catch-all `location /` extended with the same
  `Accept-Encoding` fix and `@font-face` injection the exact-match `location
  = /` already had for code-server, plus nginx's own `gzip on;`/`gzip_types`
  so disabling `Accept-Encoding` to the upstream that broadly doesn't cost
  bandwidth on JupyterLab's much heavier JS bundle. `start-notebook-wrapped`
  injects the `@font-face` plus a `:root{--jp-code-font-family:...
  !important}` override (needed `!important` — JupyterLab's own theme CSS
  sets the same variable and loads after the injected style, same
  specificity, last one wins without it). That variable is what
  CodeMirror-based editors (file editor, notebook cells) read live, but
  JupyterLab's terminal is xterm.js rendered via canvas and resolves its
  font once at construction from an explicit settings key instead — found by
  testing in a real browser and seeing the CSS-only version of this fix
  leave the terminal's rendering unchanged. `notebook--setup.sh`'s startup
  script now also seeds that terminal-extension setting (and the matching
  fileeditor-extension one), the first time the booth starts, the same
  "write only if missing" pattern already used to seed the JupyterLab theme.
  Tests: `tests/basic/test025--notebook-nerd-font.sh`.

- **VS Code's editor pane — both code-server's and the desktop app's — now
  uses the Fira Code Nerd Font too, not just the integrated terminal.**
  `codeserver--setup.sh` and `vscode--setup.sh` only ever set
  `terminal.integrated.fontFamily`; the editor kept VS Code's default font,
  which has no Nerd Font glyphs, so text containing them (rare, but real —
  found by literally typing one into a file to check) still showed tofu
  boxes even after the terminal fix above. `editor.fontFamily` is now set
  alongside it in both. Verified in a browser with the font installed
  nowhere else: Monaco's actual text-rendering elements (`.view-line span`,
  not the `.monaco-editor` container, which only carries the UI chrome font)
  correctly resolve to `"FiraCode Nerd Font Mono"` once a real file is open.

- **The codeserver variant's integrated terminal now renders the Fira Code
  Nerd Font, and its welcome banner reliably shows up.** Two independent bugs,
  found while extending the `ttyd` fix above to code-server:
  - **Font**: code-server's terminal renders client-side in the browser via
    xterm.js, same as `ttyd` — `terminal.integrated.fontFamily` in
    settings.json only named the font. The shared `start-booth-wrapped` nginx
    layer (used by code-server and every other "wrapped" variant) now serves
    the font at `/booth-assets/fonts/` unconditionally, and a new opt-in
    `WRAPPER_HEAD_INJECT` env var lets a variant's start script
    `sub_filter`-inject arbitrary HTML into the wrapped root document's
    `<head>` — empty by default, a no-op for every wrapped service that
    doesn't set it. `start-codeserver-wrapped` sets it to the matching
    `@font-face` style. Needed the same `proxy_set_header Accept-Encoding
    "";` gzip fix as `ttyd`, scoped to the exact-match root location only so
    code-server's much heavier JS bundles still transfer compressed.
  - **Welcome banner**: `99z-cb--profile.sh` used to `export TIP_SHOWN=1`
    after printing its one-time banner. VS Code (and code-server) resolve
    what env vars your shell profile sets by spawning a *hidden* probe — an
    interactive login shell whose stdout is captured and parsed as JSON,
    never shown to any user — then seed every real terminal they open
    afterward with that captured environment. The exported flag got swept
    into that snapshot and pre-suppressed the banner in every terminal a
    user actually opened. `TIP_SHOWN` is no longer exported: a plain shell
    variable still dedupes `~/.bashrc`'s own re-source of
    `/etc/profile.d/*-cb-*.sh` within one process (a pre-existing double
    invocation), but is invisible to a spawned child's `process.env`, so it
    can't leak into the probe's snapshot.

  Tests: `tests/basic/test024--codeserver-terminal.sh`.

- **The base variant's built-in web terminal (`ttyd`) actually renders the
  Fira Code Nerd Font now, not just names it.** `ttyd`'s terminal paints in
  the visitor's own browser via canvas/WebGL, not in this container, so
  installing the font system-wide and passing `-t fontFamily=...` (an
  earlier pass at this) only *names* a font — it doesn't supply one, and a
  visitor's browser without that family installed silently fell back to its
  default monospace. Two real fixes, one per web UI mode:
  - split mode (the default): `start-ttyd-split`'s nginx layer now serves
    the font as a real, cacheable asset at `/booth-assets/fonts/` and
    `sub_filter`-injects an `@font-face` referencing it into each pane's
    HTML — one fetch shared by all 4 panes rather than each embedding its
    own copy. Getting this right needed `proxy_set_header Accept-Encoding
    "";` on each pane location: `sub_filter` silently no-ops on a
    gzip-compressed body, and a real browser (unlike plain `curl`) sends
    `Accept-Encoding: gzip` by default — the same fix the `/proxy/` location
    already carried.
  - non-split fallback (`BOOTH_WEB_SPLIT=false`): no nginx sits in front of
    bare `ttyd` there, so a new `ttyd-nerd-font-index--setup.sh` bakes a
    custom `ttyd` index.html with the font embedded as a data URI, handed to
    `ttyd -I`.

  `fira-code-nerd-font--setup.sh` still installs the font system-wide too, so
  the welcome banner's Nerd Font glyph shows up for base booths as well —
  but that install was never what made the browser rendering work.
  Verified against a real @font-face load in a browser with the font
  installed nowhere else (`document.fonts` + a canvas pixel comparison of a
  Nerd Font icon codepoint against a guaranteed-fallback font), not just a
  `-t` flag or a file-exists check. Tests:
  `tests/basic/test023--ttyd-nerd-font.sh`.

- **LXQt's qterminal now opens bash instead of falling back to `/bin/sh`.**
  `dbus-launch` doesn't carry `$SHELL` into the session it starts, so
  qterminal printed "Neither default shell nor $SHELL is set to a correct
  path" and fell back to a plain POSIX shell — no `.bashrc`, no aliases,
  none of the profile setup every other terminal gets. `lxqt--setup.sh`'s
  `xstartup` now exports `SHELL=/bin/bash` inside the dbus session itself.

- **VS Code's own integrated terminal now uses the Fira Code Nerd Font too.**
  The desktop-* variants' terminal apps got the font, but VS Code's built-in
  terminal panel — both the desktop app and code-server's browser terminal —
  never had `terminal.integrated.fontFamily` set, so it kept the default.
  `vscode--setup.sh`'s `code` launcher now seeds
  `~/.vscode-data/User/settings.json` with it on first run only (never
  overwriting a later change from Settings); `codeserver--setup.sh` now
  installs the font and adds the same key to the settings.json it already
  writes on every launch (unlike the other terminals, that file is fully
  regenerated each start, to keep `python.defaultInterpreterPath` tracking
  the live venv — so a manual font change there won't survive a restart,
  matching how every other setting in that file already behaves). Also
  fixes `fira-code-nerd-font--setup.sh` to install `fontconfig` itself
  when missing — code-server carries no desktop toolkit, so `fc-cache`
  wasn't guaranteed to exist and the install failed outright. Tests:
  `tests/complex/test-boothfile-{vscode,codeserver}-terminal-font`.

- **`setup fira-code-nerd-font`, `eclipse-import-project`, and
  `idea-import-project` are recognized as valid `setup` names again.**
  `cli/src/pkg/boothfile/builtin-scripts.txt` — the Boothfile compiler's
  generated allow-list — had drifted out of sync with
  `variants/base/setups/`, so a Boothfile referencing any of the three
  failed compilation with "unknown setup". Regenerated via
  `build/gen-builtin-scripts.sh`.

- **Every desktop variant's terminal ships with the Fira Code Nerd Font.**
  A new shared `fira-code-nerd-font--setup.sh` installs the Nerd
  Fonts-patched Fira Code family (glyph icons for prompts like starship,
  and tools like lsd/exa). Each desktop's own setup script seeds its
  terminal's font on first run only, so a later font change made by hand
  is never overwritten: XFCE's `xfce4-terminal` (`terminalrc`), KDE's
  Konsole (`Shell.profile`), LXQt's `qterminal` (`qterminal.ini`), and
  Wayland's `foot` (`foot.ini`). Covers both the `setup <desktop>` catalog
  templates and the matching prebuilt desktop-* variants. Tests:
  `tests/complex/test-boothfile-{xfce,kde,lxqt,wayland}-terminal-font`.

- **Every JetBrains IDE skips its first-run prompts by default.**
  `skip-first-run` (pre-answering the Trust-and-Open, Third-Party-Plugins,
  and Data-Sharing modals — never the licence agreement, which stays a
  human's click) already existed for IntelliJ as an opt-in extension; it's
  now `auto-select` there and added, also auto-selected, to CLion, GoLand,
  PhpStorm, PyCharm, Rider, RubyMine and WebStorm. The underlying
  `jetbrains-first-run` setup script was already IDE-agnostic (it loops over
  every JetBrains IDE the image has installed), so this is catalog wiring,
  not new script logic. Live-verified against a running PyCharm booth: with
  it applied, PyCharm opened straight to the editor with neither dialog
  shown, and the seeded "declined" data-sharing answer survived untouched.

- **Every JetBrains/Eclipse IDE opens its project on launch by default.**
  `idea+import-project` and `eclipse+import-project` are now `auto-select`
  — selecting `idea` or `eclipse` alone gets the hands-off launch behaviour
  without typing `+import-project`. The same "open `$CODE_DIR` when launched
  with no arguments" trick (already proven for IntelliJ) is now a catalog
  extension, auto-selected, for CLion, GoLand, PhpStorm, PyCharm, Rider,
  RubyMine and WebStorm too — every JetBrains IDE install shares the same
  `/opt/<ide>/<ide>-starter` layout the CLI shim and `.desktop` launcher both
  funnel through, so one shared script (`jetbrains-import-project`) patches
  it for any of them: `setup jetbrains-import-project <ide>`. Unlike IDEA,
  none of these pre-generate project files first — the Gradle-vs-Eclipse
  build-system prompt IDEA's extra `gradle idea` step dodges is a JVM-only
  problem; Python/Go/PHP/Ruby/C++/.NET projects have no equivalent ambiguity
  to resolve, and JetBrains IDEs need no separate workspace import the way
  Eclipse does. DataGrip is excluded (a DB tool, not project-based).

- **RubyMine installs again.** `jetbrains--setup.sh rubymine` downloaded from
  `download-cdn.jetbrains.com/ruby/...`, which 404s for the RubyMine tarball
  specifically (its `.sha256` is present there, the tarball is not). Switched
  to `download.jetbrains.com/ruby/...`, which redirects to a working signed
  CDN URL. Found while live-verifying the new RubyMine `import-project`
  extension above.

- **A template's `requires` is now honored when ordering Boothfile `setup`
  lines, not just for auto-selecting a missing dependency.** Selecting
  `aws-cdk` alongside `nodejs` (both leave Boothfile at the default order
  band) generated `setup aws-cdk` before `setup nodejs` — "aws-cdk" sorts
  before "nodejs" alphabetically, the tiebreak used when order is equal — so
  the build failed with "npm and node are required but not found" even
  though `aws-cdk`'s `template.toml` correctly declares
  `requires = ["nodejs"]`. Anyone hitting this was affected regardless of
  selection order, since the ordering step never consulted `requires` at
  all. Boothfile segments are now topologically sorted by `requires` (an
  extension's own `requires` counts too), with order/tiebreak only deciding
  between segments that have no dependency relationship.

- **Appwrite admin create retries a slow first boot.** The health probe
  no longer lets curl retry on its own (that stacked with the wait loop).
  Creating the first account now retries a few times after the server
  answers.

- **Config TUI search ranks a name hit above a description hit.** Typing
  `python` used to focus Mojo first (alphabetical, and Mojo's blurb says
  "requires python"). Space then selected Mojo; the dependency prompt
  swallowed Ctrl+S. Name and display-name matches now sort above a match
  that only lives in the description.

- **Erlang/OTP 28 actually installs.** The 0.76.0 pin bump set the erlang
  template default and `OTP_DEFAULT_VERSION` to 28, but `erlang--setup.sh`
  still only accepted 25–27, so `setup elixir` (which auto-installs Erlang)
  and `setup erlang` failed with `Unsupported OTP version: 28`. 28 now uses
  the same RabbitMQ PPA pattern as 26/27 (`ppa:rabbitmq/rabbitmq-erlang-28`).

- **`install apt` retries a snapshot 5xx that apt-get treated as success.**
  `apt-get update --snapshot` exits 0 on `snapshot.ubuntu.com` 502/503
  (`W: Failed to fetch … ignored`). The following install then died with
  `Unable to locate package`, which is not retried — so a blip looked like
  a missing package (apt-example, turtle-example, systemlib-example).
  Update now fails closed on that warning so `cb_retry` actually runs.
  Tests: `test--apt-install-snapshot-fetch.sh`.

- **`install brew` no longer fails the image build on Linuxbrew
  caveats.** `brew install` of nginx / postgresql / redis on Linux often
  exits 1 after a successful install (systemd-only services, PATH
  shadows). `brew--install.sh` now treats that as a warning when
  `brew list` still shows every requested formula. Tests:
  `test--brew-install.sh`.

- **`python+conda+conda-pkg` packages are importable.** `setup conda`
  retargets `/opt/python` at the conda env, but `python--setup.sh`'s
  profile still put `/opt/venvs/pyX.Y/bin` first — the uv venv, which
  never saw `install conda numpy`. The series venv link is now retargeted
  at the conda env too.

- **AnythingLLM `+passwordless` skips the login password.** `--select
  anythingllm+passwordless` sets `AUTH_TOKEN` empty (AnythingLLM's
  `RequiresAuth` flag), strips a leftover `AUTH_TOKEN=` from `.env` on
  boot, and disables password protection on the running server. Not
  auto-select: with `+expose`, anyone who can reach the host port has
  full admin. Template params are `ANYTHINGLLM_VERSION`,
  `ANYTHINGLLM_PORT`, and `ANYTHINGLLM_HOST_PORT` (`+expose`). AnythingLLM
  env: `AUTH_TOKEN` (password), `JWT_SECRET` (set with a password),
  `STORAGE_DIR` (`~/.anythingllm`, `+persist`), `SERVER_PORT` and
  `ANYTHING_LLM_RUNTIME=docker` (set by `start-anythingllm`; filesystem
  agent needs `docker`). Host LM Studio:
  `http://host.docker.internal:1234/v1`. Tests:
  `test111-init-anythingllm.sh`.

- **AnythingLLM `+project-fs` bind-mounts the booth project into the
  file-system agent jail.** `--select anythingllm+project-fs` mounts the
  host project at `~/.anythingllm/anythingllm-fs/code` (run-args `-v @code:…`;
  `@code` is rewritten to the same host path as `/home/coder/code`). A
  symlink is not enough: AnythingLLM `realpath()`s and rejects targets
  outside the jail. `start-anythingllm` sets `ANYTHING_LLM_RUNTIME=docker`
  so the filesystem skill is offered, and `+project-fs` turns that skill
  on (it is off by default; `@agent list files` otherwise only searches
  empty workspace RAG). In chat: `@agent list files in code`. This is not
  workspace RAG and not `+persist`. Tests:
  `test111-init-anythingllm.sh`, `TestPrepareCommonArgs_RewritesAtCodeVolume`.

- **AnythingLLM is a catalog template.** `--select anythingllm` copies the
  official `mintplexlabs/anythingllm` image (default `1.16.1`) into the booth
  and installs `start-anythingllm`. Chat with documents using Ollama (already
  in this catalog) or a cloud provider — native in the booth, so
  `http://127.0.0.1:11434` just works. The server does not start or publish a
  port on its own: add `+autostart` to run it on boot and `+expose` to reach
  it from the host. `+persist` keeps `~/.anythingllm` in `.booth/cache` on
  this machine. Default UI port is `3001`. Pin with `anythingllm:1.16.1,13001`.
  `examples/workspaces/anythingllm-example` selects
  `anythingllm+autostart+expose+project-fs+passwordless` and checks `/api/ping` with `just run`.
  The UI works at `http://localhost:3001/` and in the globe pane
  (`http://booth:3001/`) — React Router basename follows `/proxy/<port>`,
  and pane-originated `/login` is redirected under that prefix so it does
  not nest the booth console in the iframe.
  Tests: `test111-init-anythingllm.sh`,
  `tests/complex/test-boothfile-anythingllm`.

- **AFFiNE Server starts Redis and runs Prisma without yarn.**
  The redis template only prepares `~/.redis` — it does not fork `redis-server`
  — so `affine-server+autostart` waited 60s, got connection refused, and
  exited; nginx then served 502 on `:13010`. `start-affine-server` now
  daemonizes Redis when nothing is listening. Official predeploy runs
  `yarn prisma migrate deploy`, but we COPY only `/app` from the Affine
  image (no yarn). The starter calls `prisma migrate deploy` from
  `node_modules/.bin` instead.

- **PostgreSQL startup reclaims a `booth-pgdata` volume owned by an old
  postgres UID.** The named volume is shared across booths; a later base
  image can ship `postgres` as a different uid (100 vs 112). The 0700
  data dir then made `cp pg_hba.conf` fail with `Permission denied`, and
  booth-entry's `set -e` took the whole container down. Startup now chowns
  `/var/lib/postgresql` when this image's postgres user cannot read it,
  and drops a stale `postmaster.pid` left by another container.

- **`copy --from=image:${ARG}` inlines the ARG at compile time.** Docker
  parses `--from` as a stage/image name before ARG expansion, so
  `copy --from=ghcr.io/toeverything/affine:${AFFINE_SERVER_VERSION}` reached
  the daemon as the literal tag `${AFFINE_SERVER_VERSION}` and failed with
  `invalid reference format`. The compiler now substitutes the Boothfile
  `arg NAME=value` default and errors if the ARG is missing. Hoppscotch's
  `hoppscotch/hoppscotch-frontend:${HOPPSCOTCH_VERSION}` and CloudBeaver's
  `dbeaver/cloudbeaver:${CLOUDBEAVER_VERSION}` had the same latent bug.

- **AFFiNE Desktop and AFFiNE Server are Tools catalog templates.**
  `--select affine-desktop` installs the AFFiNE Electron app (docs +
  whiteboard) on a desktop variant, AppImage from GitHub, same shape as
  Obsidian. Linux is x64 only — arm64 warns and skips; use affine-server
  or the host client instead. `--select affine-server` copies the official
  self-hosted image (`ghcr.io/toeverything/affine`) into the booth;
  PostgreSQL, Redis, and Node.js 22 are pulled in. The server does not
  start or publish a port on its own — add `+autostart` and `+expose`.
  First browser visit creates the admin account. Pin the desktop with
  `affine-desktop:0.27.4`; pin the server image with `affine-server:canary`
  (default `stable`). `AFFINE_SERVER_DATA` is `clean` (default, empty every
  booth), `seed` (`+seed`, home-seed snapshot, writes discarded), or
  `persist` (`+persist`, `.booth/cache`, writes survive on this machine).
  `examples/workspaces/affine-example` selects
  `affine-server+autostart+expose` so `just run` waits for the UI on
  :13010. Open the admin setup at `http://localhost:13010/admin/setup`
  (the globe pane cannot load Affine's `/admin/js/` SPA). Tests:
  `test109-init-affine-desktop.sh`, `test110-init-affine-server.sh`.

- **Hoppscotch is a catalog template.** `--select hoppscotch` copies the
  official `hoppscotch/hoppscotch-frontend` image (default `2026.8.0`) and
  serves the API client in the booth. No Postgres, OAuth, or admin dashboard —
  collections stay in the browser. A same-origin CORS proxy is bundled so
  requests to booth-local APIs work without the Hoppscotch Agent. Add
  `+autostart` to run it on boot and `+expose` to reach it from the host.
  Default UI port is `13000` (Hoppscotch's own 3000 collides with Node apps).
  Pin with `hoppscotch:2026.8.0,18000`. Tests: `test108-init-hoppscotch.sh`.

- **Config cycle fields take a mouse click on the option list.** Opening
  Variant (or Sudo, Egress Mode, and the other cycle fields) listed the
  values in the right panel, but `clickRightPanel` treated that pane as
  help-text-only, so a click on `notebook` did nothing — you had to cycle
  with the keys. The options are now hit-tested from the same pass that
  draws them (the `paramRowAt` pattern), and a click picks that value and
  commits, which is what Enter does after cycling there. While the field is
  being edited, `◄` `►` on the left row step the same way the arrow keys do
  (including wrap), instead of committing and re-opening the editor; and
  the help text yields so the option list stays on screen rather than
  clipping `desktop-wayland` and `terminal` off the bottom of a short
  terminal.

- **Appwrite CLI and self-hosted server are catalog templates.** `--select
  appwrite-cli` installs the official CLI from GitHub releases (`appwrite -v`).
  `--select appwrite-server` requires the CLI and installs `start-appwrite` /
  `stop-appwrite` for a self-hosted instance. Appwrite has no native install —
  the server is the official Docker Compose stack, so `+autostart` pulls in
  `dind` and `docker-compose` and starts it on boot; `+expose` publishes the
  console (default HTTP 8080 — the official installer CLI rejects ports
  longer than 4 digits, so 20080 cannot be passed through). First start
  wants about 4GB RAM. Pin with `appwrite-cli:27.3.0` and
  `appwrite-server:1.9.6`. `APPWRITE_DATA` is `clean` (default, empty every
  booth), `seed` (`+seed`, home-seed snapshot, writes discarded), or
  `persist` (`+persist`, `.booth/cache`, writes survive on this machine).
  `start-appwrite` dumps/restores Compose volumes through that tree because
  DinD cannot bind booth paths. First console user is
  `admin@example.com` / `password123`. `examples/workspaces/appwrite-example`
  selects `appwrite-server+autostart+expose` (clean) and checks CLI plus
  `/v1/health/version` with `just run`. Tests: `test107-init-appwrite.sh`.

- **The console globe bar prefills `http://booth` and keeps proxied apps
  inside the pane.** Clicking the globe opens the address box already set to
  `http://booth` with the cursor at the end, so the next keys are
  `:8080/` rather than the whole URL. A leading `:port` is accepted the same
  way. Proxied backends that `Location: /` (Appwrite's console does) used to
  resolve against the booth origin and recursively load the console UI in the
  iframe; nginx now rewrites those redirects under `/proxy/{port}/`. SPAs that
  then `fetch('/v1/…')` against the booth origin (same-origin Appwrite console)
  are forwarded to that proxy port when the Referer is a `/proxy/{port}/` pane,
  so the console gets JSON instead of the booth HTML and can finish loading.

- **The console has a Markdown-view shortcut.** Each pane's document icon
  opens the existing web view at `http://booth:8765` — viewmd, which the
  split UI now starts on that port against the project folder (`README.md`
  when present). Click again (or the terminal icon) to return to the
  session. Same path as typing `8765` in the globe bar; the nginx proxy
  also rewrites `"/api/` so viewmd's images resolve behind `/proxy/8765/`.

- **Mojo notebooks are a catalog extension.** `--select mojo+kernel` pulls
  Jupyter and registers a kernelspec named `mojo`. Modular's official
  notebooks are a Python kernel plus `import mojo.notebook` (`%%mojo` cells,
  each a complete program with `main()`); the extension auto-imports that
  magic so the first cell does not have to. The third-party `mojokernel`
  package is not used — it last shipped against Mojo 0.26 and has no
  linux/arm64 wheel. `examples/workspaces/mojo-example` includes
  `Factorial.ipynb`. Tests: `test106-init-mojo-kernel.sh`,
  `tests/complex/test-boothfile-mojo-nb-kernel`.

- **Mojo is a catalog language.** `--select mojo` installs the Mojo 1.0
  compiler (`pip install mojo` into booth Python) and a C++ compiler, and
  pulls in Python (`requires`). Pin with `mojo:1.0.0`. The official VS Code
  extension (`modular-mojotools.vscode-mojo`) auto-selects on codeserver/VS
  Code variants. `examples/workspaces/mojo-example` JIT-compiles a factorial
  with `just run 5`. Tests: `test105-init-mojo.sh`,
  `tests/setups/test--mojo-setup.sh`,
  `tests/complex/test-boothfile-mojo`.

- **Catalog version pins refreshed for 0.76.0.** Script defaults, template
  defaults, and GitHub-API fallbacks now agree on current stables, including
  the three script↔template drifts: Go `1.26.8` (N−1 of 1.27), Node.js `24`
  (current LTS), JDK `25`. Also Python `3.13.15`, kind `0.33.0`, PlantUML
  `1.2026.8`, Mermaid CLI `11.17.0`, Gradle `9.7.1`, Obsidian `1.13.8`, Julia
  `1.12.7`, Swift `6.3.3`, Scala `3.8.4` (N−1 of 3.9.0), Kafka `4.3.1`, PHP
  `8.4`, Ruby `3.4`, .NET `10.0`, Erlang/OTP `28`, Elm `0.19.2` (official
  linux x64/arm binaries), ReScript `12.3.1`, plus fallback/suggests bumps
  for buf, viewmd, Kotlin, Elixir, Exercism, Clojure, Wails v3
  `v3.0.0-beta.17`, Freeplane, and `gh`.

- **Apache mod_php, nginx php-fpm, and MongoDB auto-start are catalog
  extensions.** `--select apache+php` enables mod_php without reinstalling
  Apache (`setup apache --php-only`). `--select nginx+php-fpm` installs php-fpm
  and wires the default site (`setup nginx --fpm-only`) without reinstalling
  nginx. `--select mongodb+start` forks mongod on boot — mongodb--setup.sh only
  prepares `~/.mongodb`. LAMP / LEMP / WordPress examples wrap their demo
  `*-init` scripts as project-local templates; MEAN / MERN drop the duplicate
  mongod-start inits and select `mongodb+start`. Tests:
  `test102-init-apache-php.sh`, `test103-init-nginx-php-fpm.sh`,
  `test104-init-mongodb-start.sh`.

- **PHP Composer is a catalog extension.** `--select php+composer` installs
  Composer globally after PHP (`setup php --composer-only`), without reinstalling
  PHP — which is what a second `setup php --with-composer` would do, and which
  would also reset a pinned version to 8.4. Distinct from `+composer-install`,
  which runs `composer install` for a project's `composer.json`.
  `examples/workspaces/php-example` selects `php+composer`.
  `tests/config/test101-init-php-composer.sh` and
  `tests/setups/test--php-composer-only.sh` cover the Boothfile line and the
  `--composer-only` path.

- **Floci is a Tools catalog template.** `--select floci` installs the official
  [Floci](https://floci.io) CLI, a LocalStack-compatible local AWS emulator on
  port 4566 (no cloud account, no auth token). `floci start` needs Docker —
  `+autostart` pulls in `dind` and starts the emulator on boot; `+expose`
  publishes 4566 to the host. Dummy AWS keys are exported in every login shell,
  so `aws s3 mb s3://my-bucket` works once the emulator is up. Pin the CLI with
  `floci:0.2.1`. `examples/workspaces/floci-example` selects
  `aws-cli/floci+autostart+expose` and round-trips an S3 object with `just run`.

- **Wails v3 is a catalog language (experimental).** `--select wails` installs the `wails3` CLI
  (`go install github.com/wailsapp/wails/v3/cmd/wails3@…`) and the Linux compile
  stack Wails v3 actually needs — GTK 4 and WebKitGTK 6.0 — and pulls in Go and
  Node.js. `wails3 build` produces a Linux GUI binary. Windows is a free
  cross-compile (`wails3 build GOOS=windows`); macOS and foreign-arch Linux
  take `+cross`, which adds Docker-in-Docker so `wails3 task setup:docker` can
  build the `wails-cross` image. `examples/workspaces/wails-example` is a
  counter on the xfce variant (`backend/` Go, `frontend/` UI), so `just run`
  opens the window. `+android` adds the SDK and NDK so
  `wails3 task android:build` can emit an APK;
  `examples/workspaces/wails-android-example` is that selection as an xfce booth
  with the emulator and KVM, so `just run` installs the APK on an AVD.
  iOS still needs a Mac with Xcode. WebKitGTK's
  bubblewrap sandbox cannot create user namespaces in a booth, so the template
  sets `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` (same class of workaround as
  Chromium `--no-sandbox`). Pin with `wails:v3.0.0-beta.17`.

- **Config TUI tab clicks land on the tab you clicked.** The tab bar styles pad
  one column on each side, but the click map measured the unpadded names, so
  later tabs drifted left under the pointer — clicking the **T** of Tools
  selected AI Tools. Hit-testing now uses the same padded label the bar draws.

- **Thonny File → Open works over VNC.** Apt Thonny is 4.0.1, which calls
  zenity unless `file.avoid_zenity` is True — `file.use_zenity` is a later key
  and is ignored. Zenity over noVNC exits 255 (`This option is not available`),
  so the Open icon did nothing. `thonny--setup.sh` now wraps `/usr/local/bin/thonny`
  to set `avoid_zenity = True` on every launch (Tk dialogs, start folder
  `/home/coder/code`). `tests/setups/test--thonny-avoid-zenity.sh` locks the 4.0.1
  key.

- **Logo is an Education catalog template.** `--select logo` (plus `+autostart`
  / `+expose`) installs a web-served [JSLogo](https://github.com/inexorabletash/jslogo)
  editor on port 18610, same shape as Scratch and Excalidraw: `start-logo`,
  a desktop icon, vendored CodeMirror so the page does not fetch cdnjs.
  Hide the green turtle in a program with `hideturtle` (or `ht`).
  `examples/workspaces/turtle-example` selects it next to Python turtle so
  the same square, star, and tree exist in both languages.

- **Turtle example: Logo and Python turtle in one booth.**
  `examples/workspaces/turtle-example` is a classroom lab with the same
  square, star, and tree in Logo (`--select logo+autostart+expose`) and in
  Python turtle (Thonny + XFCE). Tcl/Tk and Xvfb are installed so
  `import turtle` works on booth Python. Try it with
  `booth example try turtle ./my-turtle` (once released) or
  `cd examples/workspaces/turtle-example && booth`.

- **Every booth now ships `lazygit`.** Installed into the base image by
  `variants/base/setups/lazygit--setup.sh`, so all variants inherit it — a
  terminal UI for git ([lazygit](https://github.com/jesseduffield/lazygit)).
  It is listed in the login welcome message next to `just`. `--select lazygit`
  still pins a version (`lazygit:0.65.0`); without a pin the setup resolves
  `latest`, with a fallback to 0.65.0 when the GitHub API cannot answer.
  `tests/basic/test022--lazygit.sh` guards PATH, version, the welcome line,
  and that the binary actually runs (`lazygit --config`).

- **Every booth now ships `just`.** Installed into the base image by
  `variants/base/setups/just--setup.sh`, so all variants inherit it — a command
  runner for project-scoped recipes ([Justfile](https://just.systems)). Create
  one with `just --init`, list recipes with `just --list`, run one with
  `just <recipe>`. It is listed in the login welcome message next to `viewmd`.
  `--select just` still pins a version (`just:1.58.0`); without a pin the setup
  resolves `latest`, with a fallback to 1.58.0 when the GitHub API cannot
  answer. `tests/basic/test021--just.sh` guards PATH, version, the welcome line,
  and that a recipe actually runs.

- **Example workspaces that have in-booth commands now ship a `Justfile`.**
  `just --list` is the front door; recipes wrap the existing scripts (`just run`,
  `just test`, `just start` / `just stop`, or `just server` / `just client` for
  MEAN/MERN/PERN). Empty, tooling-only, and autostart-stack examples are left
  without one. The original `./run-*.sh` scripts stay.

- **Popular is a short curated set, and two catalog tabs moved.** The Config TUI
  Popular chip (and `booth template list` without `--full`) now shows:
  Languages — `go`, `java`, `nodejs`, `python`, `rust`; Middlewares — `sqlite`;
  Tools — `lazygit`, `neovim`, `shell-history`; AI Tools — `claude-code`, `grok`.
  The Databases tab is **Middlewares** (`templates/middlewares/`). Browsers
  (`chromium`, `firefox`, `google-chrome`) now live under **Desktop** — there is
  no Browsers tab. **AI Tools** sits immediately after Tools. Filter chips are
  `1` All, `2` Popular, `3` Selected (`4` Local when the booth has project
  templates). The TUI opens on Popular, and a current pick is never hidden —
  reopening a booth that selected `kotlin` still shows `kotlin` on Languages.
  Everything else is still there under All / `--full`. See
  [config TUI](BOOTH_CONFIG_TUI.md).

- **Config TUI list filters sit on the search row, not as extra tabs.** Category
  tabs still partition the catalog. On those tabs the search row now ends with
  exclusive **All / Popular / Local / Selected** chips: Popular is the default
  (`primary = true` plus anything already selected, so an existing pick never
  disappears). All is the full category list. Local is templates merged from
  `.booth/templates/` and is hidden when the booth has none. Selected is the
  current picks. Typing still searches the whole tab, so a name the chip hid is
  findable; Esc restores the chip. The Config tab keeps a full-width search box.
  Click a chip or press `1`/`2`/`3` to switch; tabs that still have matches under
  a non-All chip are starred the same way a search stars them. See
  [config TUI](BOOTH_CONFIG_TUI.md).

- **The console globe bar is a full URL, host `booth` only.** Canonical form is
  `http://booth:3000/api/items`, which the pane maps to `/proxy/3000/api/items`.
  Shortcuts still work and rewrite on Enter: `3000`, `3000/api/items`, a
  localhost paste, the old `booth:3000/…` chip form, or (once a port is open)
  `/api/items`. Any other host is refused. `https://booth:…` is parsed so the
  shape is reserved, but refused until the proxy speaks TLS. The bar stays
  visible in web view so a `Cannot GET /` is editable. In web view the globe
  becomes a terminal icon (rounded square with `>`) at the front of the bar,
  in the same accent blue as the globe, that returns to the session; `←` / `→`
  walk iframe history; a page-icon before the bar shows the document title on
  hover. Open-in-new-tab follows the current path. Reserved
  booth ports `10000–10007` still refuse.

- **`exec` / `shell --silence-build` hides the `--run` bring-up.** `booth exec --silence-build --run -- ./build.sh` used to fail with `flag provided but not defined: -silence-build`. The flag is now accepted (aliases: `--quiet`, `-q`) and quiets the whole auto-start: no "starting one with booth run", no port-selection banner, no daemon banner / visit URL / container id, no "Stopping booth" or `docker stop` name echo. The command's own output is what you see. A long first image build still draws the one-line `--silence-build` progress spinner; a failed build still dumps the log. Internally this forwards `booth run --quiet`, which implies `--silence-build --no-browser` so a command-only `--run` does not open a browser or wait on the UI. `booth --silence-build --daemon` is unchanged — it still prints the URL. Unit tests cover flag parse and argv forwarding; `tests/dryrun/test031--quiet-daemon.sh` locks the banner-free daemon dryrun. See `docs/BOOTH_CONNECT.md`.

- **The same outage would have taken out a third of the catalog's downloads.** The retry above
  covers the package managers; `curl` needed nothing built, because `--retry` already handles the
  failures that matter — 408, 429, 5xx and connection/timeout errors. The gap was that only 18 of
  the catalog's 169 network calls passed it. All 169 do now.

  Two flag sets, chosen per call site rather than pasted uniformly. A plain download gets
  `--retry 5 --retry-delay 3 --retry-all-errors`. A probe, an optional fetch, or a call whose
  failure feeds a fallback gets `--retry 3 --retry-delay 2` and deliberately **no**
  `--retry-all-errors`, so a 404 still fails on the first call and the fallback fires as fast as it
  did before — `mkcert--setup.sh` dropping to its pinned version, `grok--setup.sh` to its secondary
  URL, `jetbrains--setup.sh` treating a missing `.sha` as optional.

  Fourteen call sites piped curl straight into a consumer, which a retry quietly breaks: curl
  restarts a retried transfer from the beginning, so anything already reading the stream gets the
  truncated first attempt *and then* the whole body. Harmless for `| sed` taking one match, not
  harmless for `| gpg --dearmor` (a corrupt keyring), `| dd of=` (a corrupt file), or `| bash`,
  which executes what it has already read — a mid-transfer failure runs half an installer and the
  retry then runs all of it. Those now download to a temp file first and feed the file: the apt
  signing keys for Azure CLI, Google Cloud, VS Code, MongoDB, Redis and Docker Compose; the GitHub
  CLI keyring (`-o` instead of `| dd of=`); and the ghcup, uv, rustup, Homebrew, code-server and
  **jbang** installers.

  Homebrew's was the worst of them: `bash -c "$(curl ...)"` discards curl's exit status entirely, so
  a transfer that died half way still yielded the bytes received and bash ran that truncated
  installer as if nothing were wrong. It now fails the setup instead.

  `tests/setups/test--curl-retry.sh` asserts both rules over every setup script — every network curl
  carries `--retry`, and none is piped into `bash`, `sh`, `gpg` or `dd` — so a newly added setup is
  covered the moment it lands.

- **A registry having a bad minute failed the whole image build.** A Microsoft Marketplace `503`
  failed five consecutive builds of `tests/complex/test-boothfile-code-extension` while the Open VSX
  half of the same run succeeded every time; the suite's own retry, three minutes later, passed
  clean. Nothing was wrong with the Boothfile, the id, or the image — the marketplace was briefly
  down, and neither `code --install-extension` nor any of the package managers retries on its own.

  A new `variants/base/setups/libs/retry-source.sh` supplies `cb_retry`, and every `*--install.sh`
  now routes its network-bound call through it: `apt`, `pip`, `uv`, `npm`, `yarn`, `bun`, `deno`,
  `deno-pkg`, `gem`, `cargo`, `brew`, `conda`, `cabal`, `conan`, `hex`, `luarocks`, `dotnet`, `pecl`,
  and both editor paths for `code-extension`. Three attempts with a growing backoff, and the
  command's own exit status and error output are passed through unchanged.

  It retries **only** what a second attempt can plausibly clear — an HTTP 5xx or 429, a dropped
  connection, a DNS blip, in the wording each ecosystem happens to use. A rejected package still
  fails on the very first call: `Unable to locate package`, `No matching distribution`, `404 Not
  Found` and their kin read the same on every attempt, so retrying them would only make each typo
  cost the full backoff before the build says so — and `install code-extension` promises a fast hard
  error on a bad id. Output streams live through the retry rather than being buffered, so a long
  `cargo install` still shows progress.

  `go--install.sh` keeps the hand-rolled retry it already had for `proxy.golang.org`, and
  `jetbrains-plugin--install.sh` uses curl's own `--retry`; both are declared as such in
  `tests/setups/test--install-retry.sh`, which asserts that every *other* install script routes
  through `cb_retry` — so a newly added one is covered without editing the test. `mvn--setup.sh` and
  `gradle--setup.sh` picked up the `--retry 5 --retry-delay 3 --retry-all-errors` that the rest of
  the download-based setups already used.

- **`android-example` was unusable on Apple Silicon, and the emulator crashed cryptically when
  forced.** `android-sdk--setup.sh` warns and skips the entire SDK on arm64 — correct, since Google
  only publishes it for linux x86_64 — but that made the example's SDK, build-tools, and `adb` all
  simply absent on an Apple Silicon Mac, with no way to build or test an APK at all.

  `examples/workspaces/android-example/.booth/config.toml` now forces `--platform linux/amd64` on
  both `run-args` and `build-args` by default (overridable via `CB_ANDROID_PLATFORM`, e.g. for an
  arm64 CI runner that wants the fast native skip back). Verified end-to-end: `sdkmanager`, `aapt2`,
  `d8`, `apksigner` all install and run under Docker Desktop's amd64 emulation, and `build-apk.sh`
  produces a real signed, installable APK. On a real amd64 host this is a no-op.

  The Android **emulator** itself does not work under this workaround — confirmed as three distinct
  crashes across Docker Desktop's Rosetta and QEMU backends (an unimplemented-syscall abort, a
  `ptrace` `ENOSYS` abort, and a hang resolving the virtual modem's address) — the emulator embeds
  its own hypervisor and GUI, both of which hit syscalls neither translation backend fully
  implements. `cb-android-emulator` (generated by `android-emulator--setup.sh`, shared by every
  project that installs the emulator) now detects that condition at launch and refuses with a clear
  explanation — naming the project's `device-connect.sh` real-device helper when one exists — instead
  of crashing into a wall of QEMU/Qt internals. A new `device-connect.sh` in `android-example` pairs
  and connects to a real Android device over Wi-Fi debugging instead, verified by building,
  installing, and launching the example's APK on real hardware.

- **The browser opened onto `502 Bad Gateway`.** `booth run` waits for the booth to answer before
  handing the URL to a browser, and the wait was asking the wrong door. It probed the booth's root,
  which nginx answers by itself — the terminal UI's root is a file on disk, and a wrapped variant's
  is a bare `return 302 /booth`. Both come back the instant nginx binds, with ttyd or code-server
  behind it still starting, so the wait ended early and the page that opened filled its frames with
  nginx's error page.

  Measured on a notebook booth: nginx answered at 1.44s, JupyterLab at 3.41s. Every run had a
  two-second window in which the browser could open on nothing. The terminal variant has the same
  gap, narrower — its four panes point at `/s1/`…`/s4/`, so it shows the 502 four times over.

  The wait now probes [`/__booth/health`](BOOTH_HEALTH.md), which proxies through to the service
  behind nginx and is the only answer that means the booth is up. That endpoint existed already, on
  the wrapped variants; the terminal variant now serves it too, probing session 1's ttyd. The same
  booth now opens at 3.55s — after JupyterLab, not before it.

  A host-side wait only covers startup, so the booth's own UI now polls the same endpoint. A page
  opened before the booth is ready, or still open across a `booth restart`, shows a "starting the
  booth" panel and loads its terminals or editor once they are actually there, instead of leaving
  nginx's error page on screen. Shared by every variant as
  `variants/base/setups/booth-ready.js`; see [BOOTH_UI_OVERLAY.md](BOOTH_UI_OVERLAY.md).

- **The Android emulator tests were opt-in, so they never ran.** `test-avd-persistence` and the
  android-example's `inBooth-test003` both required `CB_ANDROID_EMULATOR_TEST=1`, and nothing in the
  repo ever set it — no runner, no workflow. A full `run-automate-tests.sh` reported them as skipped
  and moved on.

  That is the wrong default for these two in particular. `test-avd-persistence` covers the one claim
  about `avd-cache` that nothing else can see: the emulator does not write a Quick Boot snapshot on
  its own way out, so if `cb-android-emulator-stop` ever stops saving, every other test still passes
  and users simply lose their device on each restart, with no error anywhere.

  They are now opt-**out**. They run wherever the environment can afford it, and the places that
  cannot are named rather than assumed — under CI, and on a host without usable `/dev/kvm`, where
  software emulation turns a ~20s boot into ~258s. `CB_ANDROID_EMULATOR_TEST=0` turns them off
  anywhere; `=1` still forces them on exactly as documented, so nothing that worked before changed.

  `CI` is checked inside the test rather than set in a workflow, so a suite added to CI later is off
  by default instead of discovering the cost the hard way. The KVM probe tests `-r` and `-w` on
  `/dev/kvm`, not merely that the node exists: it is `root:kvm`, so a user outside that group can see
  it and still not open it.

  Turning it on found it already broken, which is the argument for the change in one line. Its first
  real run failed on

  ```
  /system/bin/sh: can't create /sdcard/cb-persist.txt: Operation not permitted
  ```

  The default image is API 34, and from API 30 on scoped storage blocks `adb shell` from writing to
  `/sdcard` at all. Note which half failed: `cb-android-emulator-stop` still reported `State saved`,
  so the behaviour under test was fine and only the test's own marker location had rotted. The marker
  moved to `/data/local/tmp`, writable by the shell user and on the same userdata partition the
  snapshot captures, so it probes persistence just as well. All four cases pass now, including the
  one that matters — device state surviving into a brand new container.

- **`basic/test003` failed on a port nothing was using.** A run died on

  ```
  failed to bind host port 127.0.0.1:39386/tcp: address already in use
  ```

  after its own check had just called 39386 free. The check looked for a *listener*, and the thing
  holding the port was not one: every outbound connection is assigned an ephemeral port, and one in
  ESTABLISHED or TIME_WAIT is invisible to `lsof -sTCP:LISTEN` while still making the bind fail. The
  test picked from 30000-40000 and this host's ephemeral range starts at 32768, so most of the
  window it drew from was a range the kernel could hand out from under it.

  `pick_free_port` in `tests/common--source.sh` replaces it, and changes both halves: candidates come
  from below the ephemeral floor (read from `ip_local_port_range`, or `net.inet.ip.portrange.first`
  on macOS), so the kernel will not hand one out on its own; and a candidate is confirmed by binding
  it, which is the question docker is about to ask, rather than by looking for a listener.

  All fifteen tests that pick a port now use it, and their own copies are gone. Only test003 had been
  seen to fail, but its 30000-40000 window was the *least* exposed of them: the 40000-50000 and
  50000-60000 ranges the others drew from sit entirely inside the ephemeral range, so they were
  losing the same coin flip on every run and had simply not come up tails yet.

  Two needed more than a single port, and `pick_free_port` takes offsets for them — the whole span
  stays below the ephemeral floor, not just its first port:

  ```
  PORT="$(pick_free_port 300)"        # basic/test013: the booth port and its +300 published port
  ```

  `complex/test-port-next-skip` keeps its deterministic 1000-aligned scan and just moved window,
  from [40000, 60000] to [20000, 30000], with the bind check underneath it.

  Three tests that need two ports were not asking for two *different* ones — picking a port does not
  reserve it, so nothing stopped two calls from landing on the same number. What that would have
  broken differs by test: `basic/test012` starts its base booth while the codeserver booth is still
  running, so a shared port fails to bind; `complex/test-lifecycle-bind-port` publishes both on the
  same container, so it would ask docker to bind one host port twice; and
  `complex/test-lifecycle-name-port` uses the second as the "some other port" its override cases
  override with, so an equal pair would have passed while demonstrating nothing.
  `pick_free_port_other_than` states the requirement instead:

  ```
  PORT_A="$(pick_free_port)"
  PORT_B="$(pick_free_port_other_than "$PORT_A")"
  ```

  None of this was written down anywhere, which is why every test had reinvented it wrongly. There is
  now a `tests/README.md`: what the nine suites are and how they differ, the port rules above with
  the reasoning, and the two `set -euo pipefail` traps that silently skip a case rather than failing
  — a bare test as the last line of a loop body, and a failing pipeline inside `$( )`. Both were
  found in this repo's own tests, each having hidden a case that never ran while the suite still
  reported green.

  Nine `test-add-*` skills go with it, one per suite, each covering that suite's naming, discovery
  glob, helper library and assertion vocabulary — they differ more than they look, with three
  separate helper libraries between them — and each opening by naming the cases that belong to a
  cheaper sibling instead.

- **A booth's page outlived the booth it came from.** Run a booth, close it, run a different variant
  on the same port, and the browser hands the reused URL to the tab that is still open — which is
  still showing the first booth's page. Nothing on it belongs to what is now on that port. The
  terminal UI's panes ask a notebook booth for `/s1/` and get Jupyter's 404 framed inside the
  terminal chrome; the readiness check above makes it worse on its own, because the notebook *is*
  serving, so the gate reports "up" and loads the wrong paths with confidence.

  Readiness cannot answer this — the question is not whether a booth is up but *which* booth is.
  So each container start now mints a random `BOOTH_INSTANCE_ID`, baked into the page it serves and
  stamped on every `/__booth/health` response as `X-Booth-Instance`. When the two stop matching, the
  page is from a booth that is gone, and the UI navigates to the current booth's root instead of
  driving a stranger. Both ids must be well-formed for a mismatch to count, so an older image or a
  template that failed to substitute switches the check off rather than reloading on a loop.

  A restart mints a new id too, so `booth restart` now reloads the page rather than only its frames
  — the page is regenerated from the booth's current configuration, and the pane layout is in
  `localStorage`, so it survives.

- **The Ollama install had no bounds and no voice.** `test-boothfile-ollama` sat on one line for
  twenty-eight minutes:

  ```
  ⠋ 28m09s  [3/3] RUN ollama--setup.sh  — ⬇️  Installing Ollama v0.32.15 (arm64) ...
  ```

  That `echo` was the last thing the step printed, and the `curl` after it was
  `curl -fsSL "$TARBALL_URL" -o "$TMP/ollama.tar.zst"` — no connect timeout, no stall detection, no
  retry, no resume, no progress. `ollama-linux-arm64.tar.zst` is 1,543,177,713 bytes and GitHub
  serves it at roughly 1 MB/s, so twenty-eight minutes was the job very nearly finished, not a hang.
  A wedged socket, on the other hand, would have blocked the build indefinitely, and any reset would
  have repaid the whole 1471 MB from zero.

  The download now names its size up front, emits a newline-terminated heartbeat every 30s — the
  only kind the build progress line can display, since `curl --progress-bar` rewrites one line with
  `\r` and `build_progress.go` keeps only what follows the last `\r` on a *completed* line — and
  carries the bounds it never had: `--max-time`, `--speed-limit`/`--speed-time`, and `-C -` onto a
  `.part` file that is moved into place only after `curl` exits clean.

  ```
  ⠋ 12m40s  [3/3] RUN ollama--setup.sh  — … 700 MB of 1471 MB (47%)
  ```

  Version resolution was unbounded too, and silently produced nonsense. Unauthenticated
  `api.github.com` allows 60 requests/hour/IP; over that limit the body is a JSON error, nothing
  matches `tag_name`, and `VERSION` came back empty — building `.../download/v/ollama-linux-arm64.tar.zst`
  and failing as a 404 that named a file instead of the real cause. It is now bounded, retried, and
  validated, and says what to do (`--version <X.Y.Z>`).

- **The Ollama test was not testing the Ollama setup.** `tests/complex/test-boothfile-ollama/` ships
  its own `.booth/setups/ollama--setup.sh`. A Boothfile `setup ollama` line compiles to a bare
  `RUN ollama--setup.sh` (`compiler.go:509`) and `.booth/setups` is prepended to `PATH`
  (`compiler.go:230`) — so the project-local copy shadows `variants/base/setups/`, and the test has
  been exercising a private duplicate rather than the catalog script it claims to cover. The two had
  already drifted apart in how they parse `tag_name`. Both now carry the same fixed download and are
  byte-for-byte identical, which removes the drift but not the shadowing.

- **The published images were never actually signed.** `docker-build.sh` ran
  `cosign sign --yes --upload=false`, which computes a signature and then does not upload it, so no
  `sha256-<digest>.sig` ever reached the registry. Every release logged "Cosign: signing tag …" and
  signed nothing anyone could reach, while `build/README.md` told people to run:

  ```
  cosign verify --key ./build/cosign.pub nawaman/codingbooth:base-latest
  ```

  which answered `Error: no signatures found`. The flag has been there since the first commit of
  that script, so this covers every release to date, 0.74.0 included.

  `--upload=false` is dropped, so the signature lands beside the image and the documented verify
  command works. Nothing else changes: signing still happens only where tags are produced (the merge
  step), still skips `--rc` versions, and still retries for registry propagation — the merge job
  already runs `docker login`, and cosign reads those same credentials.

  The images published for 0.74.0 are unaffected and remain unsigned; the next release is the first
  that can be verified.

## 0.74.0

- **The Kafka install looked like a dead build for twenty-four minutes.** `test-boothfile-kafka`
  sat at one line, and the line said the download had failed:

  ```
  ⠹ 17m26s  [2/2] RUN kafka--setup.sh --version 3.7.0  — curl: (22) The requested URL returned error: 404
  ```

  Nothing was wrong. `kafka--setup.sh` tries `downloads.apache.org` first and falls back to
  `archive.apache.org`, and that 404 is the *handled* first attempt — it can never succeed, because
  the CDN carries only current releases (today 4.1.2, 4.2.1, 4.3.1) and the default is pinned at
  3.7.0. Even Apache's own `closer.lua` mirror redirector sends 3.7.0 to the archive, so there is no
  faster source for it. The archive is durable but throttled: measured at ~80 KB/s against a
  119,028,138-byte tarball, which is a legitimate twenty-four-minute download.

  The fallback `curl` was `-fsSL`, so it printed nothing for those twenty-four minutes, and the
  build progress line keeps the step's most recent output line until a newer one arrives. The stale
  404 therefore stayed on screen for the whole download — a working build wearing a fatal error.
  The obvious reach, `curl --progress-bar`, does not help: it rewrites one line with `\r` and no
  newline, and `build_progress.go` keeps only what follows the last `\r` on a *completed* line, so
  none of its meter ever reaches the status line.

  Three changes, no new default version:

  - The primary attempt's stderr is swallowed. That 404 is expected control flow on this path, and
    leaving it visible only ever mislabels the step that follows.
  - The fallback names the size up front and then emits its own newline-terminated heartbeat every
    30s, which is the one thing that does advance the progress line:

    ```
    ⠹ 8m26s  [2/2] RUN kafka--setup.sh --version 3.7.0  — … 42 MB of 113 MB (37%)
    ```

  - The fallback gets the bounds it never had: `--max-time`, `--speed-limit`/`--speed-time` so a
    genuinely dead socket is abandoned instead of ridden forever, and `-C -` onto a `.part` file so
    a reset at minute twenty does not repay the tarball from zero. The tarball is moved into place
    only after `curl` exits clean, so a partial download can no longer reach `tar`.

  This also drops a `mkdir -p "$KAFKA_DIR"` followed by `mv "$KAFKA_DIR" "$KAFKA_DIR" || true` — the
  extract path already lands on exactly that directory, so the move was a no-op whose `|| true` was
  there to hide it failing against itself.

- **Extension installs stopped crying wolf.** `libs/code-extension-source.sh` verifies each
  extension against the editor's own installed list after installing it — the check that caught
  elixir asking for a Marketplace id on Open VSX. It matched case-sensitively, and desktop VS Code
  lowercases every id it reports, so `JakeBecker.elixir-ls` came back as `jakebecker.elixir-ls` and
  the script warned:

  ```
    ✔ JakeBecker.elixir-ls
    ⚠ Not found after install: JakeBecker.elixir-ls
  ```

  one line after announcing the install had succeeded. Nothing was broken, which is the problem: it
  fired for every mixed-case id in the catalog — `Dart-Code.dart-code`, `REditorSupport.r`,
  `JakeBecker.elixir-ls` — on every desktop build, training the eye to skip the one warning that
  would have meant something. code-server preserves the publisher's casing, so only the `code` CLI
  was affected. The match is now `grep -qix`, which is what the newer
  `code-extension--install.sh` already did.

  `test--code-extension-per-editor.sh` pins it from both sides: its `code` stub now lowercases what
  it lists, the way the real one does, and a second case asserts that an id which never lands still
  warns — loosening the match must not make the verification vacuous.

- **A silenced build no longer looks like a hung terminal.** `--silence-build` hides BuildKit's
  output so a booth launch is not buried under it, but a step can be quiet for a very long time. On
  a base build, `RUN codeserver--setup.sh` spends about eight minutes inside one 224 MB `curl`
  without printing a byte, and `RUN vscode--setup.sh` another ten on pip wheels — eighteen minutes
  of a motionless terminal, which is indistinguishable from a hang. The complex test suite silences
  every build, so it reads as stuck at exactly that point.

  A silenced build now draws one line, in place, and erases it when the build ends:

  ```
  ⠹ 7m29s  [3/6] RUN codeserver--setup.sh  — Downloading code-server 4.133.0 for arm64 (224 MB)…
  ```

  The step being built, how long that step has been running, and its most recent output line. The
  clock is driven by a ticker rather than by arriving output, so it keeps moving through the silent
  stretch that made this necessary, and a `curl` progress meter — one `\r`-rewritten line that can
  reach megabytes before its newline — leaves the last real message standing instead of scrolling
  garbage. Nothing survives the build: the scrollback stays as clean as it was, and the full log is
  still printed verbatim on failure.

  The line follows the terminal rather than stderr, which is what makes it reach the place that
  needed it most. A complex test runs `codingbooth --silence-build … 2>/dev/null`, and the suite
  pipes each test through `tee` — stderr is never a terminal there, so a line drawn on stderr would
  have gone to /dev/null and the suite would have kept looking hung. When stderr is redirected the
  line is drawn on the controlling terminal instead:

  ```
  --- Running: test-boothfile-conda ---
  === Test: Boothfile Conda Installation ===
  ⠹ 3m18s  [4/7] RUN conda--setup.sh  — Preparing transaction: ...done
  ```

  and the ✅ lines land on it once the build is over, exactly as they do today.

  This is safe because of what the line is: transient, and on a stream nobody is capturing. The
  redirect still receives byte-for-byte what it received before — a captured log, a `CB_DIAG_LOG`
  trace, an expected-output fixture, a diff. What it needs is somebody watching, so it is drawn only
  while stdin or stdout is still a terminal: a daemonised run, a cron job, or CI has none and stays
  as silent as before, and `CB_NO_BUILD_PROGRESS=1` turns it off on a terminal too.

  `tests/manual/run-build-progress-manual-test.sh` shows all three paths — quiet build, failed
  build, redirected stderr — since the one case `go test` cannot exercise is the one where the line
  is drawn.

- **A quiet test suite no longer looks like a hung one either.** The same problem, one level up:
  three runners have long stretches where they print nothing at all.
  `tests/config/run-all-tests.sh` holds a parallel test's output back until it finishes;
  `tests/config-tui/run-all-tests.sh` waits on a VHS recording — ttyd, a headless browser, then an
  encode; and `examples/workspaces/run-example-tests.sh` sends every example to `.<example>.log` and
  then blocks on `wait`, which for an example that builds a booth image from scratch can be fifteen
  minutes of a completely still terminal between "Started example" and the summary table.

  Each now draws one line, in place, and erases it before anything else is printed:

  ```
  Started example: django-example (pid: 54120)
  ⠹ 1 running · django-example 6m02s  — #8 184.3 Collecting numpy
  ```

  The new `tests/progress--source.sh` is the shared piece — `progress_draw`, `progress_clear`,
  `progress_elapsed`, `progress_tail` — and it follows the same rules as the CLI's build line
  deliberately: drawn on the controlling terminal rather than stdout, so a captured log or a CI
  transcript is byte-for-byte what it was; nothing drawn for the first second, so a suite of fast
  tests does not flicker; and `CB_NO_TEST_PROGRESS=1` to turn it off. Where the runner has one, the
  detail after the em dash is the last line of the busiest test's log — the build step it is sitting
  on, which is the actual answer to "is this stuck?".

  `tests/config/test98-suite-progress-line.sh` pins the two failures that would otherwise go
  unnoticed: that an inactive line writes nothing at all — a stray escape code in a captured log is
  invisible until it corrupts a fixture comparison — and that what is drawn is always erased.

  With no terminal nothing is drawn and the config runner keeps printing its `--heartbeat` report,
  which is the only signal a CI log ever had. And because two writers on one line is garbage, a
  runner that owns the terminal line runs its children with `CB_NO_BUILD_PROGRESS=1`: the booth
  build underneath stays silent and is reported through the line instead. The complex suite is
  unchanged — it streams each test live and draws nothing itself, so booth's own build line is what
  shows there.

- **One credential path per platform, and only one of them mounted.** A template that seeds a host
  tool's configuration has to name a different path on each platform — pip keeps its per-user config
  in `~/.config/pip` on Linux, `~/Library/Application Support/pip` on macOS and
  `~/AppData/Roaming/pip` on Windows — so the natural spelling is three `-v` entries pointing at one
  container target, letting `FilterMissingVolumeMounts` drop the ones whose host path is absent.
  Two things went wrong with that.

  Where two alternatives both existed — easy on a Mac, where a tool may write both `~/.config/X` and
  `~/Library/Application Support/X` — both survived the filter, and Docker then refused to start the
  container at all: `Duplicate mount point`. A template written the obvious way could stop a booth
  from running. Where none existed, the run printed one "Skipping volume mount" line per platform,
  every time, for a mount nobody had asked about.

  The filter now indexes bind mounts by container target. The first alternative that exists is kept
  and the rest are dropped, so the duplicate never reaches Docker; and the skip is reported once per
  target, naming what was tried — `no host path exists for /etc/cb-home-seed/.config/pip (tried:
  ~/.config/pip, ~/Library/Application Support/pip, ~/AppData/Roaming/pip)` — rather than once per
  candidate. A single-candidate mount is reported exactly as before. `pip Config` is the first
  template to use the pattern and `templates/README.md` writes it down, including the part that
  matters: order the alternatives so the most authoritative path for each platform comes first,
  because first-that-exists is what wins.

- **The config suite can be narrowed, and `--verbose` no longer eats its own log.** 95 tests is a
  long way to go to re-check one, so the runner takes `--only <glob>` (repeatable), `--jobs N`, and
  `--heartbeat SECS`, and `--help` now lists them.

  `--verbose` also stopped silencing the image build: on a run that is sitting on one, the build is
  the only thing worth showing, and it is what the operator asked for by typing the flag.

  The dangerous one was quieter. A test's `finally` cats its own log back out on a `--verbose`
  failure, and the runner used to capture that same test's console output into the same file —
  `cat file >> file`, which never reaches EOF. One `--verbose` run of a failing test grew a 362GB
  log and killed bash with an xrealloc overflow. The runner now captures into `out--<name>.log`,
  kept separate from the test's own `log--<name>.log`, and the cat goes through a snapshot so the
  same mistake cannot be made by hand either.

- **JetBrains IDEs started through their booth shim were missing the JDK and Python environment.**
  The starter `jetbrains--setup.sh` generates carried a stray double quote:
  `source /etc/profile.d/60-cb-jdk--profile.sh"    2>/dev/null || true`. The unbalanced quote glued
  that line to the next one, so the shim ran a single `source` of a bogus path containing a newline
  — and `2>/dev/null || true` swallowed the failure. Neither profile was ever loaded, silently,
  for every IDE launched that way. Both lines are fixed and guarded.

- **The setup-script tests no longer skip on macOS — and eleven of them were skipping.** Each of
  those tests runs an install/setup script that opens with `[[ $EUID -eq 0 ]] || exit`, and reached
  for `fakeroot` to satisfy it. macOS ships no `fakeroot`, so all eleven printed `SKIP` and exited
  0, and the suite still reported itself green — 204 assertions that nobody was running, on a
  machine where no CI runs them either. Nothing privileged was ever needed: the tests stub `sudo`
  and the tool binary and assert on the command line the script emits. bash takes `EUID` from the
  environment when one is present, so `env EUID=0` satisfies the guard with no privilege and no
  dependency. `fakeroot`'s other trick, faking `chown`, was never used by any of the eleven.

  Clearing the guard exposed six real failures underneath, all of them differences between the
  bash 5 + GNU userland a booth runs and the bash 3.2 + BSD userland macOS provides:

  - `"${arr[@]}"` on an **empty** array is "unbound" under `set -u` in bash 3.2, which aborted
    `cargo--install.sh`, `code-extension--install.sh`, `codex-code-extension--setup.sh` and
    `libs/code-extension-source.sh`. Now written `${arr[@]+"${arr[@]}"}`, the same form
    `docker-build.sh` already used for this exact reason.
  - `date +%s%3N` is a GNU extension; BSD `date` copies the letter through, handing JetBrains
    `…:17873317983N` as a millisecond timestamp. It now falls back to whole seconds ×1000.
  - `wc -l` output is padded on BSD (`·······1`), and a test compared it as a string.

  The suite now passes 13/13 on both macOS and Linux — the same result on both platforms for the
  first time.

- **An optional `source` is guarded rather than trusted to fail quietly.** 26 setup scripts wrote
  `source /etc/profile.d/…  2>/dev/null || true` to mean "load this if it is there". Bash 3.2
  treats a `source` that cannot find its file as fatal and exits the shell *before* the `|| true`
  is consulted, so on a Mac host those scripts died where bash 5 sails through. They now test with
  `-f` first; `go--install.sh`, which sourced a glob, loops over the matches instead. The three
  scripts that genuinely *require* the JDK profile still source it unguarded, so a missing profile
  stays a loud failure rather than becoming a silent misconfiguration. The convention is written
  down in `docs/BOOTH_SETUP.md`.

- **The code-server download is bounded too — the third one of these.** `codeserver--setup.sh`
  handed the whole job to coder's `install.sh`, which fetches the ~224MB `.deb` with a bare
  `curl -#fL -C -`: no connect timeout, no stall detection, no retry. A connection that crawls at a
  few KB/s is therefore never abandoned — it is ridden until GitHub hangs up, which cost one build
  three minutes to gain 0.2% of the file and then failed the whole image with
  `curl: (18) Transferred a partial file`. Since that curl lives in *their* script, our flags
  cannot reach it.
  
  Their `fetch()` reuses `$CACHE_DIR/<file>` whenever it already exists, so the package is now
  fetched first, into exactly that path, with the same bounds as the claude-code and JDK downloads:
  connect timeout, `--speed-limit`/`--speed-time` so a dead connection is dropped in a minute
  instead of ridden for three, and `--retry` with `-C -` so an interrupted transfer resumes rather
  than repaying 224MB. `install.sh` then prints `+ Reusing …` and goes straight to `dpkg`. The size
  is named up front, because a quarter-gigabyte download that prints nothing for fourteen minutes
  is indistinguishable from a hang — and the natural response, `^C`, discards the layer.
  
  The version is resolved first (the same redirect probe `install.sh` uses) so the cached filename
  matches what it will look for, and `--version` pins it to that release rather than letting it
  resolve "latest" a second time. A failed probe falls back to the plain installer, so the floor is
  the old behaviour, never worse. Verified end to end on a slow link: 224MB in fourteen minutes,
  followed by `+ Reusing ~/.cache/code-server/code-server_4.133.0_arm64.deb`.

- **A booth can reach services on the host now — and `booth--info` says how.** The tunnel story
  was one-directional: `booth--expose` carries a container port out to the host, but a booth that
  wanted to talk to a PostgREST, a database, or a language server running *on* the host had
  nothing to dial. Docker Desktop happens to resolve `host.docker.internal` on its own, so the
  trick worked on macOS and Windows by accident and was never mentioned anywhere; on native Linux
  the name does not exist unless the run asks for it, so the same command failed. Every booth is
  now started with `--add-host host.docker.internal:host-gateway`, which makes the name work the
  same way on all three platforms.

  Two variables carry the facts to scripts: `BOOTH_HOST_NAME` (the name to dial) and
  `BOOTH_HOST_IP` (the host's own IPv4 address on its network — the one to hand to someone else,
  or to put in a config that wants an address rather than a name). The address is resolved on the
  host at launch by asking the kernel which source address it would use to reach the outside
  world; a firewall that refuses even that unsent UDP connect falls back to scanning the
  interfaces, and a machine with nothing but loopback simply leaves the variable unset. Both show
  up in `booth--envs`, and `booth--info` gained a **Host Access** section that resolves the name
  and prints what it points at, with the caveat that matters: a host service bound to `127.0.0.1`
  only is unreachable from inside any container — it has to listen on `0.0.0.0`.

  Under `--dind` and `--egress` the booth borrows a sidecar's network namespace, and docker
  rejects `--add-host` on a container that does that ("conflicting options: custom host-to-IP
  mapping and the network mode") — passing it there would not merely lose host access, the booth
  would fail to start. In those modes the alias is set on the sidecar that owns the namespace
  instead, which the booth then shares. Egress policy still applies: the name resolves, but the
  allowlist decides whether the connection goes through.

- **A slow link no longer looks like a wedged `claude-code` install — and the binary is
  actually verified now.** `claude-code--setup.sh` fetched the ~330MB binary with a bare
  `curl -fsSL`: no `--connect-timeout`, no `--speed-limit`/`--speed-time`, no `--retry`, no
  `-C -`. Without any timeout a half-open connection hangs the build forever rather than
  failing, a single transient reset or GCS 5xx costs the whole `RUN` layer, and `-s` silences
  the progress meter so BuildKit printed `Downloading from ...` and then nothing at all. On a
  slow link that step legitimately runs for the best part of an hour and is indistinguishable
  from a hang; the natural response is `^C`, which discards the layer and restarts from byte
  zero. The transfer now aborts if it genuinely stalls (under 1KB/s for 60s) rather than
  hanging, retries with resume so a reset partway does not repay the whole 330MB, starts from
  a clean path so `-C -` cannot trip over a stale complete file and take a 416, and names the
  size up front so the wait is legible. The two small metadata fetches got timeouts and
  retries as well.

  Separately, the manifest lookup read `."linux-arm64".checksum` when the platforms live
  under a `platforms` object, so it always came back empty. The bash-regex fallback that would
  have covered for it only runs when `jq` is absent — and `jq` ships in the base image — so
  the empty checksum reached a `[[ -n "$CHECKSUM" ]]` guard that read it as "this manifest
  carries no checksum" and skipped verification. Every build since has installed an unverified
  binary. The path is fixed, the guard is now a hard failure rather than a silent skip, and
  the fallback learned to read `size` too. Verification is what makes resuming a partial
  download safe, so the two fixes belong together.

- **The JDK download got the same treatment.** `jdk--setup.sh` fetched its ~180MB tarball with
  a bare `curl -fSL ... 2>/dev/null` — same missing timeouts, stall detection, retries and
  resume as `claude-code--setup.sh`, and the `2>/dev/null` discarded curl's progress meter *and*
  the `-S` error text it was there to show, so several minutes passed with nothing on stdout.
  It now names the tarball size before starting (a best-effort `HEAD` — a failed probe just
  omits the line), aborts a genuinely dead transfer instead of hanging, and retries with resume.
  `--no-progress-meter` replaces the blanket `2>/dev/null`, so real errors and retry notices
  reach the log while the meter still stays out of it. The download starts from a clean path so
  `-C -` cannot trip over a stale complete file and take a 416. The jbang bootstrap fetch got
  connect and total timeouts too.

  The size probe lowercases headers before matching rather than using awk's `IGNORECASE`, which
  is a gawk extension: Ubuntu ships mawk, and while HTTP/2 lowercases header names, an HTTP/1.1
  vendor sends `Content-Length` — under mawk that combination would have silently produced no
  size at all. Verified against both temurin and corretto with the base image's own mawk.

- **The test suites no longer open browsers.** Opening the booth's UI is on by default, so
  every suite that starts a UI booth threw a window at whoever ran it — and, in daemon mode,
  waited for the port to answer first. `CB_BROWSER=false` is now set by
  `tests/run-automate-tests.sh`, by `tests/common--source.sh` (so a single test run on its own
  is quiet too), and by the config/config-tui runners whose tests do not source it; the example
  tests that start a UI booth pass `--no-browser`. `tests/basic/test019--browser-open.sh` unsets
  it — the default is what that test checks.

- **Host-side test scratch files go through `TMPDIR`.** `basic/test012--booth-health.sh` wrote
  curl's response body to `/tmp/health.$$` by name. Where `/tmp` is not writable — a sandboxed
  shell, a hardened CI image — curl still fetched the page and still printed its status through
  `-w`, but exited 23 on the failed write, so the `|| echo "000"` fallback appended to a status
  already on stdout: `200` became `200000`, every probe missed, and a healthy booth timed out
  after 90s. The failure then reported `last=` empty, because the variable it printed is only
  assigned on success. Fixed both, and the same `/tmp`-by-name capture in
  `complex/test-connect-run-port`.

## 0.73.0

- **A booth that serves a UI now opens it in your browser.** The port was printed and left
  there; every start ended with the same copy-paste. Booth now opens `http://localhost:<port>`
  itself, in foreground and daemon mode alike, and is off by a flag — `--no-browser`,
  `CB_BROWSER=false`, or `browser = false` in `config.toml` (`--browser` forces it back on for
  one run).

  **It waits for the port to actually answer.** `docker run -p` publishes the host port when the
  container is *created*, so the port accepts connections long before anything inside is
  listening — opening on that signal lands the browser on a reset connection, which is the
  failure this feature would otherwise be famous for. Booth polls its own URL and opens on the
  first HTTP response (any status: code-server and Jupyter both answer the front door with a
  redirect to a login page). In foreground mode the wait runs alongside the container and is
  dropped the moment it exits, so a booth that dies during startup does not leave a goroutine
  polling a dead port.

  **A booth given a command never opens one.** `-- bash` and `--variant terminal` — the same
  thing, since the variant resolves to `base` plus a `bash` command — run in the terminal booth
  was launched from and serve no page. The command list, not the variant, is what decides.

  Opening is cross-platform and never fatal: `open` on macOS, `url.dll,FileProtocolHandler` on
  Windows, `xdg-open` and its fallbacks elsewhere, the Windows browser via `wslview`/PowerShell
  under WSL, and `$BROWSER` first wherever it is set. A host with no graphical session (on Linux,
  no `DISPLAY` and no `WAYLAND_DISPLAY` — the usual shape of a booth over SSH) or no opener
  installed gets a warning naming the URL, and the booth carries on.

- **`--offset-base` unpins `+OFFSET` host ports from the booth port.** A published port written
  as `+4567` has always resolved to `boothPort + 4567`, and locally that is the whole point: the
  booth port is the one number that already differs between two booths of the same project, so
  tying every service to it is what keeps them off each other's published ports. A booth alone on
  a cloud host has no such collision to dodge, and its front door sits on a port it did not pick —
  443, or whatever the platform assigned — so counting service ports from it lands them nowhere in
  particular.

  The base is now a setting of its own: `--offset-base <n>`, `CB_OFFSET_BASE`, or `offset-base` in
  `config.toml`. Unset, it *is* the booth port, so nothing about an existing booth changes.
  `booth --port 443 --offset-base 20000` puts the UI on 443 and publishes `+4567` on 24567.

  **A base of `0` is legal**, where a booth *port* of 0 is not: it makes each `+OFFSET` resolve to
  the offset itself, which is how a config written entirely in offsets publishes at stock ports
  without being rewritten.

  Both resolvers moved together — the host-side one in `ResolveRelativePorts`, and `booth--expose`
  inside the container, which reads a new `BOOTH_OFFSET_BASE`. That variable is exported **only**
  when the base has actually been moved; otherwise `booth--expose` falls back to `BOOTH_HOST_PORT`
  and gets the same answer, so an ordinary booth's environment is unchanged. The duplicate-host-port
  check still runs after resolution, so a moved base that lands a service on the booth's own port is
  refused by name rather than handed to docker.

## 0.72.0

- **`idea+skip-first-run` pre-answers the modals that block a fresh booth's first IDE launch.**
  Opening IntelliJ in a new container meant clicking through up to four dialogs over noVNC — and
  because the container home is recreated per run, it was every start, not once. The opt-in
  extension seeds three of them: the **Third-Party Plugins Notice** (`updates.xml` →
  `THIRD_PARTY_PLUGINS_ALLOWED`), **Trust and Open Project** (`trusted-paths.xml`, the workspace
  path only — never the "trust all projects in this folder" checkbox, since that prompt exists to
  stop untrusted project code executing), and **Data Sharing** (`consentOptions/accepted`,
  recorded as *declined*). After it, first launch shows one dialog instead of four.

  The **User Agreement is deliberately left alone**, and the extension is **off by default** for
  the same reason: accepting a licence for someone at image-build time is a legal act, not a
  configuration default. You opt in; the EULA still gets a human.

  Every value was **measured, not derived** — an IDE was clicked through by hand and its config
  tree diffed across a clean exit. This matters more than it sounds: an earlier hand-written
  attempt put the EULA key in `~/.java/.userPrefs/jetbrains/privacy_policy/` at version `2.1`,
  and the real record turned out to be version `1.0` in a Java Preferences node whose name is
  character-encoded. Nothing here would have been got right by reasoning about it.
  `tests/setups/test--jetbrains-first-run-setup.sh` pins all three, including an assertion that
  no EULA acceptance is ever written.

- **IntelliJ now sees every JDK in the image, not just the one `JAVA_HOME` points at.**
  `setup jetbrains-jdk` writes a `jdk.table.xml` naming all of them — six, in
  `all-java-example` — and is auto-selected with the `idea` template. To be precise about what
  this does and does not fix: a JetBrains IDE *does* auto-detect the `JAVA_HOME` JDK, so a
  single-JDK booth already resolves a Maven project without this (measured on IDEA IC 2025.2.3,
  which detects `/opt/jdk25` and names it `temurin-25` by itself). What it adds is the other
  five, and a table that does not depend on `JAVA_HOME` aiming at the right JDK or on the IDE's
  naming convention continuing to match what projects ask for.

  Two details carry the whole feature:

  - **The names are not free choice.** SDKs are registered as `<vendor>-<major>` — `temurin-25`,
    `corretto-17` — which is what a JetBrains IDE calls a JDK it finds by itself, and therefore
    what projects already carry in `.idea/misc.xml`. `examples/workspaces/java-example` has asked
    for `project-jdk-name="temurin-25"` since it was committed; matching the convention is what
    makes it resolve without touching the project. The JDKs are also linked into `~/.jdks`, one
    of the dirs the IDE scans, so its own detection agrees with the table instead of offering a
    duplicate entry for the same JDK.
  - **Java 8 needs a different table.** It has no module image, so the Java 9+ shape — `jrt://`
    class roots and per-module `src.zip` source roots — describes nothing that exists on a pre-9
    JDK. Those get `jar://` roots for `jre/lib` and `jre/lib/ext` and a flat `src.zip` instead.
    (The IDE re-derives roots at runtime, so this is about handing it a table that is correct for
    the JDK it names rather than about resolution failing outright.)

  Unlike plugins, this cannot live in the image: the SDK table is per-user config, and the
  container home is recreated per run. It is written to `/etc/cb-home-seed`, which `booth-entry`
  copies into the home **no-clobber** — so it appears in a fresh container, and a user who edits
  their SDK list from Project Structure keeps their version from then on. Selecting an IDE
  without Java, or Java without an IDE, both stay valid: the setup skips. Coverage is
  `tests/setups/test--jetbrains-jdk-setup.sh` (hermetic, 18 cases, including the Java 8 branch)
  and `tests/config/test96-init-jetbrains-jdk.sh`.

- **JetBrains IDE plugins can now be baked into the image, by id, for every IDE in it.**
  `install jetbrains-plugin <id> [more...]` is the `*--install.sh` sibling of
  `install code-extension`, and `jetbrains-plugin-pkg` makes it selectable:
  `--select "idea/jetbrains-plugin-pkg:IdeaVIM,6317"`. Until now the only route was
  `setup jetbrains-plugin <ide> "<plugin>"`, which names exactly one IDE and one plugin and
  defers the install to a startup script that re-runs on every container start — so a booth
  needed network at launch to open its IDE with the plugins it was configured for. That path
  still works; this one puts the plugins in the image.

  What made it possible is that a JetBrains IDE's plugin dir can be moved out of the user's
  home: `jetbrains--setup.sh` now writes `idea.plugins.path=/opt/jetbrains-plugins/<product>`
  into the install's `bin/idea.properties`, so a plugin installed at build time survives into a
  container whose home is recreated per run — and the IDE's own headless `installPlugins`
  honours it, so the plugin the user installs from the marketplace UI at runtime lands beside
  the baked ones. The new `libs/jetbrains-source.sh` holds the discovery both scripts share
  (IDEs from `product-info.json`, plugin dir, marketplace build id), and `cb-has-jetbrains.sh`
  joins `cb-has-vscode.sh` / `cb-has-desktop.sh` as a guard.

  Three behaviours are deliberate, and each is one the VS Code sibling gets to skip:

  - **Both id forms are accepted.** A plugin page carries an xmlId and a number; the IDE's
    installer answers `unknown plugins` for a number, so numeric ids are resolved through the
    marketplace API first. This is not a convenience — Lombok's xmlId is the two-word,
    misspelled `Lombook Plugin`, and a space cannot travel through a whitespace-split template
    param, so `6317` is the *only* way to name it from `booth config`.
  - **Unpinned installs and `@version` installs take different routes.** `installPlugins` picks
    a compatible build and pulls in dependencies but has no version argument, so a pin is
    fetched from the marketplace directly — exact, and resolving nothing.
  - **A plugin that fits none of the IDEs in the image is the failure, not one that fits only
    some.** `org.jetbrains.plugins.go` has no IntelliJ IDEA Community build; a booth with IDEA
    and PyCharm may legitimately take a plugin into one of them. Landing nowhere fails the
    build. And with no JetBrains IDE at all the install *skips* rather than failing, because
    `jetbrains--setup.sh` itself skips on a non-desktop variant — the ids are not at fault.

  Lombok itself gets a curated `setup lombok-idea` (selected as `idea+lombok`), the counterpart
  to the `lombok-eclipse` that already existed, rather than being named by id. That is not
  ceremony: reaching it through the generic param leaves `arg JETBRAINS_PLUGIN_PKGS=6317` in the
  Boothfile, a bare number that tells its reader nothing, because the spaced xmlId cannot survive
  an unquoted template expansion. A curated script *can* pass it whole, so the installer now
  splits comma lists without re-splitting an argument that already arrived intact.
  `examples/workspaces/java-example` uses it, and keeps `jetbrains-plugin-pkg` selected but empty
  so the escape hatch is visible where anyone would look for it. Coverage is
  `tests/setups/test--jetbrains-plugin-install.sh` (hermetic, 19 cases, no Docker) and
  `tests/config/test95-init-jetbrains-plugin-pkg.sh`.

- **Desktop icons — and where you put them — now survive a restart, on XFCE and LXQt.**
  `xfce+desktop-icons-cache` / `+desktop-icons-shared` and the matching `lxqt+…` pair mount two
  things as one feature: `~/Desktop`, which is the launcher set, and the desktop environment's own
  layout file, which is where each icon sits. Both desktops write that layout themselves —
  xfdesktop on every drag, pcmanfm-qt when the desktop process exits — so the mount is the entire
  mechanism; no script arranges anything.

  The pairing with the existing seed is what makes this better than `--persist-home` for the
  purpose. Launchers from `/etc/skel/Desktop` are re-seeded no-clobber on *every* start, so a
  rebuilt image's new icon appears and takes a free slot while icons you placed stay put.
  `--persist-home` stops seeding after the first run, so a new icon never shows up at all.

  Cache and shared are the same mount with different git posture: `.booth/cache/` is local and
  gitignored, `.booth/shared/` is committed. Four sample gitignores ship for the shared side,
  because `~/Desktop` is not as safe to commit as it looks — the image's own launchers land in it
  on every start, and committing one freezes a stale copy forever against the no-clobber seed.

  **KDE is deliberately absent.** Plasma keeps the whole desktop layout in a single `~/.config`
  file that KConfig rewrites by rename, and every route into a mount fails on that: a file bind
  mount gets `EBUSY`, a symlink is replaced by the first save, and copying the file in and
  mirroring it back is actively destructive — Plasma regenerates the layout at session start, and
  the mirror then overwrites the good saved copy with the regenerated one. `--persist-home`
  remains the answer on KDE. The Wayland variant has no desktop icons at all (`/etc/skel/Desktop`
  becomes waybar buttons there), so nothing to persist.

- **`data-example`'s Sales Explorer dashboard now waits to be asked.** It used to be started for
  everyone by `.booth/startup.sh`, whether or not anyone opened it. Now nothing listens on port
  13000 until its **desktop icon** is clicked, and that click does the whole job: `npm install` if
  `node_modules` is missing, start the server, open it in a browser window. It is registered
  through `cb-web-icon.sh` — the same helper that puts JupyterLab on the desktop — so `cb-web-open`
  handles the start-if-not-listening step from the descriptor, and `start-sales-explorer` does the
  same thing from a shell. Boot now only waits for PostgreSQL and seeds the `demo` database.

  Making that icon selectable is the more reusable part. A setup script hand-referenced from a
  generated Boothfile drifts it away from its `# Configured by:` line, and `booth config` then
  refuses to touch the file — the project stops opening in the config TUI. So the `setup` line is
  *generated*, by a project-local template in `.booth/templates/project/sales-explorer/` that names
  the hand-placed `.booth/setups/sales-explorer-icon--setup.sh`. It shows up in the TUI and in
  `--select` under "This project", and a flagless `booth config` re-derives the whole selection
  from the existing `.booth/` and reproduces both files byte for byte. This is the first example to
  use the mechanism `docs/AGENT.md` describes.

  `Sales-Explorer.ipynb` also ships with its outputs cleared — it was carrying 250 KB of base64
  PNGs from someone's *Run All*, which is a quarter of a megabyte of diff noise for charts the
  notebook draws in a second.

  The example now has a host test, which it never had: one booth asserts the launcher is on the
  desktop, the descriptor carries the start command, **nothing** answers on 13000 at boot, and the
  starter then serves seeded rows. The boot assertion watches the port for fifteen seconds rather
  than curling it once — a restored autostart spawns the server and returns, so a single curl races
  node's bind and a connection refusal is indistinguishable from "never started". Written the
  cheap way, that assertion passed against a deliberately restored autostart.

- **Flutter is now something a booth can be configured for, and with it Dart — which the catalog
  had no route to at all.** `setup flutter` installs the SDK under `/usr/local/flutter-<version>`
  behind a `flutter-current` symlink, so the last install wins without rewriting the profile, and
  both `flutter` and `dart` land on `PATH`. `FLUTTER_VERSION` defaults to `latest`, resolved from
  Google's own release manifest rather than a hard-coded URL: `current_release.stable` is a build
  hash, so it is looked up in the release list to get the version and the archive path, and an
  unknown pin fails with the eight most recent stables printed rather than a 404. The engine
  artifacts are precached at build time, so a booth starts ready instead of stalling on a
  several-hundred-megabyte download the first time anyone types `flutter`.

  The web target needs nothing else — `flutter build web` compiles, and
  `flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0` is reachable at
  `/proxy/8080/` on the booth port, in the existing web pane. Android and Linux desktop each need
  more than the SDK, so they are extensions rather than weight everybody pays for: `+android`
  (`requires` the Android SDK, and through it a JDK) and `+linux-desktop` (clang, cmake, ninja,
  pkg-config, GTK 3 headers). `+vscode-ext` is auto-selected and carries `Dart-Code.dart-code` and
  `Dart-Code.flutter`. Deliberately, `flutter` itself requires **nothing**: forcing a JDK and a
  multi-gigabyte Android SDK on someone who wants `flutter build web` is the wrong default.

  Two failures worth naming, because neither is visible from a `--version` check:

  - **The SDK is a git checkout.** Installed by root and run as `coder`, git refuses it with
    `detected dubious ownership` and the flutter tool dies before it does anything —
    `git config --system --add safe.directory` is the whole fix, and it has to come before the
    first run.
  - **The tool writes back into its own tree** (`bin/cache`) at runtime, and `chown coder` is the
    *wrong* repair. `booth-entry` remaps `coder`'s UID to the host user's at container start, so a
    build-time owner only matches by luck — the same trap that made `/usr/local/share/code-server`
    work on most Linux hosts and fail on macOS. Mode bits are UID-agnostic, so this follows conda,
    code-server and cypress in using them.

    The permission pass has to be the **last** thing each of these setups does, which is worth
    stating because getting it wrong fails in the least helpful way available. Every `flutter`
    invocation can rewrite `bin/cache` — even `flutter --version`, which re-runs
    `update_engine_version.sh` — so a version echo in a summary block after the `chmod` leaves
    `engine.stamp` root-owned at `0644`. At runtime the tool regenerates that stamp with `mv`,
    and `mv` over an unwritable target does not fail: it *asks* ("overriding mode 0644"), on a
    stdin nothing will ever answer. The booth hangs forever, with no error and no output.

  Android configuration goes through env vars in a `/etc/cb-flutter.d/` drop-in rather than
  `flutter config --android-sdk`, which writes to the *build-time root user's* settings file and
  would be invisible to the person who needs it. The `flutter` and `dart` wrappers source that
  directory, so a non-login shell — `booth -- ./build.sh`, which never reads `/etc/profile.d` —
  sees the SDK too. Add-ons contribute a drop-in instead of the wrapper knowing about them.

  `+android` also had to solve two things that only appear when you actually run `flutter build
  apk`, both of which made the stock-defaults booth build nothing:

  - **The Android SDK's default API level trails what Flutter compiles against.** `android-sdk`
    defaults to API 34; Flutter 3.44.9 compiles against 36, and Gradle stops with `Flutter requires
    Android SDK 36`. The number is read out of the installed Flutter SDK
    (`FlutterExtension.kt`'s `compileSdkVersion`) and that platform installed if absent, rather
    than pinned here where it would rot on the next Flutter release. An `ANDROID_API` pin is left
    alone — this only ever adds a platform.
  - **Gradle installs SDK components on demand, into a directory that was read-only.**
    `android-sdk--setup.sh` leaves its tree at `a+rX`, which is right for its own aapt2/d8 path but
    makes the NDK install AGP triggers fail with `The SDK directory is not writable`, killing the
    build during project configuration. `+android` relaxes the tree, deliberately in *its* setup
    rather than in `android-sdk--setup.sh`: it is a cost of the Gradle path, so only booths that
    opted into it pay, and the Android SDK keeps the tighter mode for everyone else.

  Verified end to end rather than by `--version`: the same app builds for web (`main.dart.js`),
  Android (`app-debug.apk`) and Linux desktop (a native binary), and `flutter test` drives a
  headless render. Note the first `flutter build apk` downloads the NDK and CMake, so it is
  several minutes; later builds are not.

  `unsupported-arch = ["arm64"]` throughout, checked against Google's manifest rather than assumed:
  across 728 releases every `dart_sdk_arch` is `x64`, and no arm64 stable Linux build has ever been
  published. As with the Android SDK, the setup warns and exits 0 rather than failing the build.

## 0.71.0

- **Examples no longer ship the author's home directory, and two more are `booth config`-openable.**
  Nine examples — `clang`, `claude`, `csharp`, `firebase`, `fsharp`, `jetbrain-exmple`, `kind`,
  `server`, `zig` — carried `# Generated by: booth config /home/nawa/dev/git/CodingBooth/...` in 18
  committed `.booth/` files, because `booth config` echoes its target path into the header verbatim and
  had been run with the path as an argument. Every `booth example try` download carried it.
  `claude-example`'s even named a `bash-example` folder that no longer exists. All nine are now
  path-free. Eight were fixed by editing the comment line, which is safe precisely because those files
  carry no `.generated` — their guard status is unchanged either way.

  `jetbrain-exmple` is the one to remember: the folder name is misspelled, so it matches no
  `*-example` glob and was invisible to the sweep that found the other eight. It turned up only in a
  final check across `examples/workspaces/*/`.

  `playwright-example` and `zig-example` are now genuinely generated — regenerated from their own
  recorded selection, `.generated` fingerprint committed, verified as same-command fixed points, so
  `booth config` opens them with their selection preloaded instead of guarding them as hand-authored.
  `zig-example`'s regeneration is also what removed its host path.

  Attempting the same across the whole catalog produced a more useful answer than a migration: of 65
  examples, 28 would have their directives changed by replaying their own header (templates evolved
  after the files were written), 30 record no selection to replay at all, and 2 more that *do*
  regenerate cleanly — `cache-example` and `empty-example` — were deliberately left alone, because an
  empty selection writes no Boothfile and the fingerprint would then cover only `config.toml` while the
  guard kept flagging the Boothfile. `empty-example`'s hand-written Boothfile of commented-out examples
  is the point of that example. The measurements are recorded in `docs/TODO.md` so the next attempt
  starts from evidence.

  Separately, `browser-shared-example`'s `config.toml` opened with `# Configured by: booth config for
  browser-shared-example` — prose, not a command. That is the guard's "header but no fingerprint →
  adopt it" case, so `booth config` believed it had written that hand-authored file and would have
  overwritten it without warning. The line is gone, and the file now correctly refuses to be
  regenerated.

  A new `tests/config/test93-booth-files-are-clean.sh` keeps the host-path fix from rotting: it fails
  on any committed `.booth/` file carrying a home path other than the container's own `/home/coder/`,
  and on any `.generated` entry naming a file that is not there. It needs no Docker, and both
  assertions were checked in the failing direction as well as the passing one.

  It deliberately does **not** assert that every fingerprint still matches, which was the obvious rule
  to reach for and is wrong: a *mismatching* hash is the guard working — it is how the tool knows a
  generated file was hand-edited, and it is what makes it protect those edits.
  `playwright-polyglot-example` sits in that state on purpose, and "fixing" it by deleting
  `.generated` makes things worse rather than better, because a header with no fingerprint is
  *adopted* and overwritten silently. Both directions were verified against the real binary and the
  finding is recorded in `docs/TODO.md`.

- **New `pocketbase-example`: a trip calendar with a database, a REST API and an admin UI out of
  one `go build`.** PocketBase is used the way it is meant to be used from Go — as a library the
  program embeds, not a binary it downloads — so `main.go` gets the collections, the generated REST
  API and the admin UI for free and adds one route of its own. The example is *Tripboard*: five
  invented days in Portugal, drawn as one 24-hour row per day, where a hotel night is cut at
  midnight and each day keeps the half it owns. That cut happens in Go (`trip.go`), which is the
  point of the custom `/api/trip` route: the built-in `/api/collections/trip_events/records`
  returns the same records, just not arranged the way a calendar reads them.

  Nothing is carried in a database file. The schema and the demo trip are Go migrations under
  `internal/migrations/`, so deleting `pb_data/` and restarting rebuilds the trip identically — and
  the repo has no `pb_data` to go stale. The Go toolchain is pinned in the Boothfile, PocketBase
  (`v0.39.9`) in `go.mod`, and container port 8090 is mapped to host 8090, so the calendar and the
  admin UI at `/_/` both open in the host browser with no port plumbing.

  Its `.booth/Boothfile` and `config.toml` are `booth config` output rather than hand-written, and
  ship with the `.booth/.generated` fingerprint beside them, so `booth config` opens the example in
  its TUI instead of guarding it as hand-authored — and an open-and-save with no edits reproduces
  both files byte for byte.

- **Both agent manuals now say how to author a Boothfile that `booth config` will still open.**
  `docs/AGENT.md` — the copy baked into every image at `/opt/codingbooth/AGENT.md` — described a
  world of `.booth/Dockerfile` and never mentioned `booth config`, so an agent following it wrote
  the Boothfile by hand. That is a one-way door: the fingerprint in `.booth/.generated` stops
  matching, and from then on `--no-tui` refuses to run without `--overwrite` while the TUI opens
  behind a warning dialog that will not save until the user types "overwrite" in full. It now leads
  with *Change the Environment (Boothfile / config.toml)*: regenerate from the `# Configured by:`
  line at the top of the Boothfile, carry the whole `--select` forward (it replaces rather than
  merges, so an omitted template is a tool that silently disappears), and hand the command to the
  user — `booth config` is host-side, and there is no CLI inside the container (only the `booth--*`
  helpers; the in-booth way to see what is installable is `ls /opt/codingbooth/setups/`).

  The rest of the file was brought forward with it, because half a correction is worse than none:
  *Add a Built-in Tool*, *Add a Simple apt Package* (now `--select apt-pkg:htop,jq`), *Experiment
  Before Committing* and the decision tree all handed out `.booth/Dockerfile` recipes, and *Modify
  Runtime Config* told the reader to edit `config.toml` by hand — the exact move the guard punishes;
  it now maps each setting to the flag that writes it. *Create a Custom Setup Script* gains the part
  that was missing entirely: a script in `.booth/setups/` needs a `setup <tool>` line, and the way to
  get one without hand-editing is a project-local template under `.booth/templates/`, which keeps the
  booth generated. `.booth/Dockerfile` is documented as what it actually is — a still-supported
  fallback used only when no Boothfile exists, with the Boothfile winning (and saying so) when both
  are present. The file tree, the "What NOT to Do" table, Troubleshooting and the closing checklist
  were corrected to match.

  `AGENTS.md` gains the repo-side rule — anything we *ship* with a `.booth/` (example workspaces,
  `tests/complex/` fixtures) must be generated, commit `.generated` as the third file, run from
  inside the workspace so an absolute path does not land in the committed header, avoid restating
  a value that equals the template default, and prove the round trip rather than assume it. The
  `setup-work` skill's workspace anatomy now matches.

- **The Android emulator can keep its device between booth restarts.** New `avd-cache` extension
  puts `~/.android` in `.booth/cache/`, so installed apps, settings and signed-in sessions survive
  container recreation instead of being rebuilt from scratch every start — and a restore takes
  7–16s where a cold boot takes 26–38s.

  Three things had to come with it, each found by testing rather than by reading:

  - **Stopping is not symmetrical with starting.** The emulator does not reliably write a Quick
    Boot snapshot on its own way out: measured here, neither `adb emu kill` nor a SIGTERM leaves
    one behind. The device then restores from whatever snapshot was written last and silently
    rolls back the session — persistence that looks like it works and does not. New
    `cb-android-emulator-stop` saves state first, then kills, and the extension's docs lead with
    it.
  - **Cached lock files are worse than no cache.** The emulator records a running instance in
    `avd/running/` and takes `*.lock` files beside the AVD, and a container exit is always an
    unclean exit as far as it is concerned. Cached, that stale lock made every subsequent start
    fail with `A snapshot operation for 'booth' is pending and timeout has expired` — a dead
    emulator holding the door shut. The launcher now clears them before starting.
  - **A cached AVD must not outlive a fix to the launcher.** Creating the AVD only when absent is
    fine while `~/.android` is ephemeral; cached, it means "create once, ever". An AVD built
    before the device-profile fix would have kept its unusable `hw.mainKeys=yes` forever. Each AVD
    now carries a stamp of the recipe that built it and is recreated when that recipe changes.

  Off by default: at ~2.8 GB it is by far the largest cache extension, against kilobytes for shell
  history.

  Covered by `tests/complex/test-avd-persistence`, which is host-side and starts the booth twice —
  the only way to prove state survived, since a test running inside one container cannot observe
  the next one. It writes a marker on the device, stops with `cb-android-emulator-stop`, destroys
  the container, and reads the marker back from a fresh one. That is the assertion that matters:
  if the stop command ever stops saving, every in-booth test still passes while users silently
  lose their device on each restart.

- **A password-protected base UI now asks for the password on its own page, with the username
  already filled in.** `--public` sets `PASSWORD`, and the four terminal panes were protected by
  ttyd's own HTTP Basic auth (`-c coder:$PASSWORD`). That means the browser's native credential
  dialog — and its username box belongs to the browser, starts empty, and cannot be prefilled by
  anything the server sends. The only way to fill it in was to know that the answer is always
  `coder`, which is why the CLI printed `https://coder@localhost:PORT` and a `Login username:`
  line: an attempt to seed that dialog through the URL, which browsers increasingly flag as a
  phishing pattern.

  The gate moved up to nginx. `start-ttyd-split` mints 32 random bytes per container start and
  bakes them into the generated config as the one accepted value of a `booth_auth` cookie; `/`,
  the panes, and `/proxy/{port}/` redirect to `/login` without it, and the booth-message API
  answers 401 (a redirect would hand the overlay's `fetch` the login page as "JSON"). `/login`
  serves a booth-styled form with the username prefilled — editable, since only `coder` is
  accepted but pretending the field is decorative would be worse — posting to a new
  `/booth-messages/api/login`, which checks the password and sets the cookie. nginx replays
  `Authorization: Basic …` toward each ttyd, so the panes keep their own credential on
  10001–10004 while the browser never sees a 401 and never opens the native dialog.

  Two things this turned up. `absolute_redirect off` is not optional: nginx builds `Location`
  from the port it listens on, so the gate was sending browsers to `localhost:10000` — the
  container-internal port — instead of the published one, which is broken for every booth and
  doubly so behind the Caddy TLS proxy on 10443. And `map_hash_bucket_size 128` has to be
  declared before any `map` block: a 64-character token does not fit the default 64-byte bucket,
  and nginx rejects the directive as a duplicate if a `map` has already been parsed.

  It also closes a hole that predates it. `/booth-messages/api/` was never behind ttyd's auth, so
  on a `--public` booth anyone who could reach the port could `POST .../shutdown` with no
  password at all. It is gated now.

  Unchanged where there is no password: the map collapses to `default 1`, every gate is a no-op,
  `/login` bounces to `/`, and nothing is injected upstream. `tests/basic/test018--base-ui-login.sh`
  drives the real `--public` path end to end — TLS included — through all eight behaviours.

- **Octave notebook plots come back as images instead of ASCII art.** The Octave kernel was
  configured with `plot_settings = dict(backend='gnuplot')`, on the reading that `backend` names
  the Octave graphics toolkit. It does not. In `octave_kernel`, `backend` selects the *delivery*
  mode, and only a value starting with `inline` turns on figure capture — everything else means
  "draw live and send nothing back". With no display server in the notebook variant, drawing live
  put gnuplot on its `dumb` terminal, so `plot(x, y)` returned several hundred lines of `#` and
  `+` text art in place of a figure, preceded by the `using the gnuplot graphics toolkit is
  discouraged` banner. The setting is now `dict(backend='inline:gnuplot', format='png')`, which
  picks the same toolkit *and* keeps capture on: cells now carry a real `image/png`.

  The warning banner had a second cause. `octave--setup.sh` wrote its `graphics_toolkit` and
  `warning ("off", …)` defaults to `/etc/octave/octaverc`, which Octave never reads — its
  system-wide startup file is the one under `octave-config -p LOCALSTARTUPFILEDIR`. That file is
  now the one that carries the settings (via a guarded block sourcing `/etc/octave/octaverc`, so
  there is still one obvious file to edit), and it silences `Octave:gnuplot-graphics` rather than
  the unrelated id it named before. It also stopped forcing gnuplot unconditionally: on a desktop
  variant with a real `DISPLAY` and the qt toolkit present, Octave's own default is left alone.

  Fixing the built-ins was not enough on its own: `octave-example` carried verbatim copies of all
  three octave scripts in its `.booth/setups/`, and the compiler prepends that directory to `PATH`,
  so the copies — not the built-ins — were what the example actually ran. `.booth/setups/` is for
  scripts an example genuinely adds (`lamp-init--setup.sh`, `wp-init--setup.sh`, …); these were
  leftovers from an editing session, committed alongside a `.Trash-1000/` folder, Jupyter
  checkpoints and an `octave-workspace` dump in the same sweep. All of it is now gone, so the
  example runs the real setups, and `.gitignore` covers the artifacts so they cannot drift back in.

  A `test-boothfile-octave-nb-kernel` complex test now drives a plotting cell against the kernel
  over the real Jupyter protocol and asserts the reply is an `image/png` with no text art and no
  warning. The kernelspec-only check the other notebook kernels use passes just fine while plots
  are unreadable, which is how this survived.

- **Catalog authoring is one skill now — `setup-work` — and it covers fixing, not just adding.**
  `setup-add` only ever described the five files a *new* setup needs, but the catalog's real
  traffic is edits: version bumps, exposing a knob, arch bail-outs, a guard that was missing.
  `setup-work` keeps the add path and adds a modify path (a version bump is three edits — script
  default, `[params]` default, `suggests` — or the pin silently does nothing) and a fix path (a
  symptom-to-layer table, because the same "tool is missing" reports as a bad `LEVEL`, an absent
  guard, or an unreferenced param depending on which layer broke).

  It also writes down the loop nobody had written down: a setup script copied to a project's
  `.booth/setups/` overrides the image's, so a script change can be exercised against the
  *released* base image without rebuilding anything, and `--dryrun --templates-path` answers every
  param and ordering question with no Docker at all. Each change gets a folder the user can open —
  a new `examples/workspaces/<name>-example` when they want one, the existing workspace that
  already reproduces a bug when there is one, a throwaway otherwise — and the skill names that
  folder every turn. Tests are held to `docs/TODO-SETUP_PROOF.md`'s standard (make the tool do the
  work) rather than the `--version` grep the old skill taught. `setup-add` stays as a pointer.

- **The catalog's authoring docs no longer describe a repo that does not exist.**
  `docs/AGENT_TEMPLATE.md` documented extensions only as subdirectories, a form the catalog uses
  zero times against 194 inline `<name>--extension.toml` files, and omitted ten keys the loader
  accepts — including `display-detail`, which 225 templates set, and `variadic`, `primary`,
  `sudo`, `[files.*]`, and the `cache-*` / `shared-*` pairs. `docs/BOOTH_SETUP.md` gave the
  startup path as `/etc/startup.d/` in two places and `/usr/share/startup.d/` in a third; 41
  setups use the latter and none use the former. Both are corrected, and `BOOTH_SETUP.md` gains a
  reference for the shared helpers that were documented nowhere — `skip-setup.sh`, `cb-has-*.sh`,
  `code-extension-source.sh`, and the `cb-web-icon.sh` / `cb-desktop-icon.sh` pair that 26 setups
  call and `test90` enforces.

  The four docs now point at each other and say which is which — patterns
  (`templates/README.md`, which nothing in the repo linked to), schema
  (`AGENT_TEMPLATE.md`), scripts (`BOOTH_SETUP.md`), recipes (`AGENT_RECIPE.md`) — and `AGENTS.md`
  lists them as catalog-authoring references instead of filing them under "helping users", which
  had been steering agents away from the guides for this repo's own `templates/` tree.

- **`keytool` and `jarsigner` now work in scripts, not just interactive shells.** `jdk--setup.sh`
  registered java, javac, jar, jcmd, jps and jstack with `update-alternatives` but not the signing
  pair, leaving them reachable only through the `JAVA_HOME/bin` that `/etc/profile.d` adds. A login
  shell reads that file; `booth -- ./build.sh` does not, since it runs via `runuser -u coder --`.
  So anything that signed an artifact from a script — an Android APK, a JAR, a self-signed TLS
  cert — failed with `keytool: command not found` while working perfectly when typed by hand, which
  is the worst version of this bug: it only appears in automation. Both are now registered
  alongside the rest. New `tests/complex/test-boothfile-jdk-tools` asserts all eight tools resolve
  in a non-login shell, that `keytool` executes, and that it can actually produce a keystore.

- **A selected template can no longer stop a booth from starting by asking for hardware the host
  does not have.** `FilterMissingDevices` drops a `--device` run-arg whose host node is absent,
  with a warning, exactly as `FilterMissingVolumeMounts` already did for bind mounts whose host
  path is missing. Before this, `--device /dev/kvm` on a machine without KVM — Docker Desktop on
  macOS, virtualization disabled in BIOS, a nested VM without nested virt — failed in `docker run`
  before the container existed (`error gathering device information ... no such file or
  directory`), which is a hard stop rather than a degradation. Only the missing flag/value pair is
  dropped; the rest of the run-args are untouched.

  This generalizes beyond Android: any template asking for `/dev/dri`, a serial device, or a GPU
  now degrades the same way. It is the run-args counterpart of the rule the setup scripts already
  follow when they warn and skip on an unsupported architecture.

- **Android is now something a booth can be configured for, rather than hand-written.** There was
  no Android anything in the catalog — a project that needed to build an APK had to hand-roll the
  whole thing in its `Boothfile`: fetch the command-line tools zip, move it to the
  `cmdline-tools/latest/` path `sdkmanager` insists on, pipe `yes` at the license prompts, then
  install platform-tools, a platform and build-tools by hand. `setup android-sdk` does that, with
  `ANDROID_CMDLINE_TOOLS`, `ANDROID_API` and `ANDROID_BUILD_TOOLS` as args so a rebuild cannot
  silently move the toolchain under the app. It `requires` java, because `sdkmanager` is a Java
  program and the failure otherwise is an unhelpful one at build time.

  The emulator is a separate `+emulator` extension rather than part of the SDK: the system image
  is multiple gigabytes, and building an APK never needs it. It also installs the X11, GL and
  audio client libraries the emulator binary links against even under `-no-window`, without which
  it dies at load time long before reading an AVD. That list includes `libpng16` and `libxkbfile`,
  which are easy to miss: they are pulled in by the Qt libraries the emulator bundles, so a
  headless `-no-window` boot succeeds without them and only `emulator -version` — or anything
  touching the UI path — fails, with `libpng16.so.16: cannot open shared object file`.

  On a desktop variant the emulator extension also installs an **Android Emulator** desktop icon
  and Development menu entry, backed by a `cb-android-emulator` launcher. A bare `emulator` with
  no AVD does nothing useful and an unaccelerated one exits with an error, so a naive launcher
  would look like a double-click that did nothing; this one creates an AVD on first run (deriving
  the package spec from whichever system image is installed, so it follows `ANDROID_API`) and
  chooses hardware or software acceleration from whether `/dev/kvm` is usable. It runs in a
  terminal so first-run AVD creation and any failure are visible.

  The AVD is created against a device profile (`pixel_6`, overridable with `CB_AVD_DEVICE`) rather
  than `avdmanager`'s bare defaults, which are actively broken for an emulator: with no `-d` it
  writes `hw.mainKeys=yes`, meaning "this device has physical Back/Home keys, so do not draw the
  on-screen navigation bar". An emulator window has no physical keys, so nothing draws them and
  nothing responds — the app cannot be left. The same defaults give a 320x640 mdpi screen, far
  below what Android 14's system UI expects, and `hw.keyboard=no`, so the host keyboard never
  reaches the guest. The launcher fixes all three and names the software rasterizer explicitly,
  since a booth has no GPU for `auto` to find.

  `+kvm` is the third piece, and it is safe to select anywhere: a host without `/dev/kvm` now
  drops the device with a warning (see the `FilterMissingDevices` entry above) rather than failing
  `docker run`. It is off by default only because it is useless without the emulator. Notably it
  carries **no** host-specific gid. The device node keeps its host `root:kvm 0660` ownership
  inside the container, which `coder` cannot open; the obvious fix is `--group-add <the host's kvm
  gid>`, which is unportable and fails silently on any other machine. Instead a `startup--45.sh`
  hook relaxes the mode container-side, which is safe because `/dev` in a container is a private
  tmpfs — verified: the host's node is still `660 root:kvm` afterwards.

  Without KVM the emulator does not fall back on its own, it refuses to start outright (`x86_64
  emulation currently requires hardware acceleration!`); `-accel off -gpu swiftshader_indirect`
  runs it in software. Measured on the example: boot to `sys.boot_completed` takes ~20s with KVM
  and ~258s without, and the APK installs and reaches the foreground either way — so an
  unaccelerated emulator is viable for a one-shot check and miserable for an edit-run loop.

  Google publishes the platform tools, build tools and emulator for linux x86_64 only, so both
  setups warn and skip on arm64 rather than failing the build, and both templates carry
  `unsupported-arch`.

  New `examples/workspaces/android-example` builds a signed, verifying APK from a one-Activity
  app using `aapt2`/`javac`/`d8`/`apksigner` directly — no Gradle, and so no network — which
  makes it a real test of the toolchain rather than of the package mirror. It passes
  `--min-sdk-version`/`--target-sdk-version` to `aapt2 link` explicitly, which the Android Gradle
  Plugin would otherwise inject from `build.gradle`: undeclared, `targetSdkVersion` falls back to
  `minSdkVersion` and then to 1, and Android 14+ refuses to install anything targeting below API
  23 with *"app isn't compatible with your phone"* — a message that sounds like an ABI mismatch
  and is really a deprecation floor. Nothing else catches it, because such an APK still builds,
  signs, verifies under v1/v2/v3, and installs fine on the emulator; the example's test asserts
  both values are present.

## 0.70.0

- **A build that cannot reach the GitHub API installs viewmd 0.5.0, not 0.2.0.**
  `viewmd--setup.sh` asks the GitHub releases API to resolve `latest` and falls back to a
  pinned default when the answer comes back empty. That call is anonymous and rate-limited,
  so the fallback is an ordinary outcome on a busy runner rather than an edge case — and the
  pin had stayed at `0.2.0` while upstream reached `0.5.0`, so those builds quietly produced a
  booth three minor versions behind, announced only by the one warning line in the build log.

  The pin is now `0.5.0`. Checked against the release rather than against the tag name: both
  `viewmd-linux-amd64` and `viewmd-linux-arm64` download at `v0.5.0`, both match the
  `SHA256SUMS` entry the script's `awk` looks for, and the binary reports `0.5.0`.

## 0.69.0

- **Puppeteer and Selenium now work on Apple Silicon, and Chrome says why it cannot.** Both
  setups were hard-wired to Chrome for Testing, which Google builds for `linux64` only — the
  API's stable channel lists `linux64, mac-arm64, mac-x64, win32, win64` and nothing else for
  Linux. On an arm64 Docker host that meant Selenium failed the build outright and Puppeteer
  installed an x86-64 binary that died with `rosetta error: failed to open elf` on first launch.
  Selenium's `aarch64` branch claimed to route around it via `@puppeteer/browsers`, but that
  fetches from the same CDN, so it was dead code that could never have worked. Debian Bookworm
  *does* build `chromium` and `chromium-driver` for arm64, so on arm64 both setups now use those
  instead: Puppeteer gets `PUPPETEER_EXECUTABLE_PATH` and skips the pointless download, Selenium
  gets a matched chromium + chromedriver pair behind the usual `chrome` / `chromedriver` names.
  Same engine, no API change, and the two complex tests that were skipping on every Mac now run.
  The Bookworm repo dance — add, pin `APT::Default-Release` to Ubuntu, install, remove, refresh —
  moved into `cb-install-chromium.sh` so `chromium-browser`, `selenium` and `puppeteer` cannot
  drift apart on the pinning or the cleanup.

  Google Chrome itself has no such fallback — Chromium is a different browser, not a build of
  Chrome — so `google-chrome--setup.sh` keeps skipping on arm64, but it no longer does it
  silently. It printed `Chrom installation is not supported.` and `exit 0`, which meant the image
  built green and the missing browser surfaced only when someone tried to run it. It now explains
  what happened, why, and the three ways forward (`chromium`, `firefox`, or Chrome on the host
  Mac against the port the booth exposes), and leaves a `/usr/local/bin/google-chrome` stub that
  repeats it at runtime instead of `command not found`. The stub never overwrites a real wrapper,
  so selecting `chromium` alongside it still wins.

  **The principle: a tool upstream never built for your architecture warns, it does not fail.**
  One absent browser must not take down a build in which every other setup succeeded.

- **`booth config` says up front which tools cannot install on your machine.** Templates declare
  `unsupported-arch` + `unsupported-arch-note` in `template.toml`; the TUI marks those rows with
  `!`, opens the detail panel with an amber *Not available on arm64* block, and warns on select —
  while still allowing the selection, because the booth does build without it. `booth template
  show` prints the same note. Only `google-chrome` is flagged today; `chromium`, `firefox` and
  `playwright` all have arm64 builds and are deliberately not. Guarded by
  `test92-arch-unsupported-is-declared.sh`, which also holds the warn-don't-fail rule above.

- **`build-all.sh` printed `✔ BASE` and `All builds completed successfully` over a base image it
  never rebuilt.** On macOS every local build had been a silent no-op: `docker-build.sh` expands
  `"${no_cache_arg[@]}"`, and when `--no-cache` is absent that array is empty — which bash 4.4+
  (every Linux) expands to zero words but bash 3.2, the bash macOS ships, rejects as an *unbound
  variable* under `set -u`. The build aborted at that line. Two things then hid it: the abort left
  the previous image tagged and dated as if current, and the `trap 'CleanupStaging' EXIT` ended the
  script with the cleanup's status rather than the failure's, so the caller saw exit 0. Found only
  because a newly added setup script kept coming back `command not found` inside a booth built from
  an image that had, in fact, not changed in a day.

  The array expansions now use `${arr[@]+"${arr[@]}"}` (the idiom `build-all.sh` already used for
  `DOCKER_FLAGS`). The status masking is fixed with a `BUILD_COMPLETED` flag rather than the
  obvious `trap 'rc=$?; …; exit $rc'` — measured, not assumed: on bash 3.2 a *fatal* shell error
  runs the EXIT trap with `$?` still `0`, so re-raising `$?` would have kept reporting success for
  precisely the failure class that caused this. A build that does not reach the end of the function
  now cannot exit 0.

- **The whole `CONFIG-TUI` suite was dead on macOS — 18 tests reporting as product bugs.** The VHS
  runner shelled out to `timeout 120 vhs …`, and `timeout` is GNU coreutils: macOS ships neither it
  nor Homebrew's `gtimeout` by default. It exited 127, vhs never started, no frame was ever
  captured, and every test then failed asserting on files that nothing had written. The suite's
  own dependency gate checked `vhs`, `ttyd` and `ffmpeg` but not `timeout`, so it ran instead of
  skipping. Now resolved through `run-with-timeout`, which prefers `timeout`, then `gtimeout`, and
  otherwise runs unguarded — a bash watchdog was written first and backed out after measurement:
  it needs the command backgrounded, and a backgrounded vhs cannot reach ttyd
  (`net::ERR_CONNECTION_REFUSED`), so the guard broke the thing it was guarding.

  That left 2 of 18 failing — `test14-tui-preserve-pin` and `test18-tui-slash-pin` — which looked
  like a param-pin data-loss bug in `booth config` and were not: **both were the same BSD/GNU
  divergence one layer down, in the tests' own fixtures.** Each seeds its scenario by hand-pinning
  a value with `sed -i 's/…/…/' Boothfile`. BSD sed reads the *script* as `-i`'s backup suffix and
  the filename as the script, exits 1, and changes nothing — so the pin under test was never
  written, and the assertion that it "survived a save" failed against a file that had never held
  it. Instrumenting the binary settled it: `existingArgs` reached `buildPreSelection` with
  `PLAYWRIGHT_VERSION:latest`, never `1.58.2`. The pin-preservation code was working the whole
  time, and a manual non-TUI reconfigure preserved `1.58.2` correctly.

  Both now use a `sed-inplace` helper that picks the GNU or BSD form by feature detection, and —
  more importantly — **assert that the seed landed** before testing anything. A fixture step that
  can fail silently makes the test that follows meaningless in whichever direction the bug
  happens to push it. The same bare `sed -i` in `test-cache-mount`'s cleanup was fixed with the
  matching `sed_inplace` helper in `tests/common--source.sh`.

- **Seven `CONFIG` tests failed on macOS and passed on Linux, for the same reason twice over.**
  `test90-web-servers-have-desktop-icon.sh` used `\+` inside a basic `sed` regex — a GNU
  extension that BSD `sed` reads as a literal plus — so the substitution never matched and every
  `--start` lookup came back empty. The `--id` lookup had it too, which meant the "web-service ids
  are unique" assertion had been silently checking nothing on macOS. Both switched to the portable
  `[ =][ =]*`.

## 0.68.1

- **`curl … /booth | bash` hands off to the installer again.** The piped install
  aborted with `BASH_SOURCE[0]: unbound variable` instead, for anyone following the
  one-liner in `docs/AGENT_SETUP.md`. Shipped in 0.68.0; 0.67.0 and earlier are fine.

  The wrapper spots a piped invocation by comparing `$0` against the shell names,
  because piped there is no script path to compare. The bare `bash` arm of that
  comparison had been replaced with a placeholder that can never match — a debugging
  edit that rode along, unnoticed, with the commit adding the test for it. `sh` and
  `zsh` still matched, so the only form that broke was the one every doc advertises.

  Falling past the handoff is not a graceful degradation: piped, `$0` is `bash` and
  `BASH_SOURCE` is empty, so the next thing the wrapper does — `realpath
  "${BASH_SOURCE[0]}"`, to resolve its own location — reads an unset element under
  `set -u` and kills the script. The handoff branch is first in the file precisely so
  that path resolution never runs on a `$0` that is not a path.

## 0.68.0

- **Every text box in the config TUI now takes `←`, `→`, `Home` and `End`, and draws
  its caret where the cursor actually is.** A mistyped module path had to be
  retyped from the mistake onward, because the cursor could only ever sit at the end
  of what was typed.

  Half of that was invisible rather than missing: four of the six text fields already
  moved a cursor on `←`/`→` and already inserted at it, but **every one of them drew
  the caret glued to the end of the value**. Moving the cursor therefore looked like
  nothing had happened, and the next character appeared somewhere the caret said it
  would not. `caretText` now draws the cursor at the cursor, at all six sites, as a
  **reversed cell** — the way a terminal draws its own — covering the character it is
  on, or the blank cell past the end of the value. Reversing a cell that is already
  there means the text does not shift as the cursor walks it, which a glyph wedged
  between two characters would have done.

  The reverse is written as `\x1b[7m` … `\x1b[27m` by hand rather than through a
  lipgloss style, because a style ends its output with a full reset: that would also
  drop the background the field is painted with and leave the rest of the row
  unstyled. `27` turns off reverse and nothing else. Two padding calculations — the
  search box and the confirmation field — counted the value with `len` and now use
  `lipgloss.Width`, since those escapes cost bytes and no columns.

  The keys themselves come from one `moveTextCursor` helper rather than four copies of
  the same switch, the same way one `typedText` already answers "what text does this
  key contribute" for all six fields: a field cannot grow its own idea of Home if there
  is only one. It answers before the field's own switch does, so an open edit claims
  `←`/`→` from the tab bar for as long as it is open — that was already true, and now
  `Home`/`End` cannot fall through to "jump to the first row" either.

  Two fields gained more than movement. The **search bar** is the only one drawn in a
  box of fixed width, and it used to window on the end of the query; `windowAround` now
  windows on the cursor, so `Home` in a long query brings the head of it — and the caret
  — back into view instead of scrolling both off the left edge. The **overwrite
  confirmation** had no cursor at all: characters appended and Backspace only ever ate
  the last one. Typing that word in full is the only way past that dialog, so mistyping
  it has to be fixable in place.

  Positions are byte offsets, which stays correct because every one of these fields
  already filters its input to printable ASCII — one byte, one column.

- **The config TUI takes the mouse now: click a tab, a row, a checkbox, a parameter;
  scroll with the wheel.** No flag — `booth config` asks the terminal for mouse
  reporting and handles clicks and the wheel; motion and releases are ignored, since a
  release would double-handle every click and there is nothing here to drag.
  Hit-testing needed no new bookkeeping, because the screen is a fixed stack of rows
  (`contentHeight()` subtracts exactly the seven it is not) and **both left panels
  already render one line per row** — `buildConfigRows` makes group headers rows, so a
  click is `rows[scrollOff + y - 4]` with no guessing. The one panel that does not work
  that way is the right one, where wrapped description text of unpredictable length sits
  above interleaved label headers and value rows: rather than reconstruct that in the
  handler — a second copy of the arithmetic, and the copy is what drifts — the detail
  renderers now hand back the line→row map they filled while drawing, re-keyed by the
  same scroll offset that moved the lines. Same for the tab bar (`tabLabels` draws it and
  hit-tests it) and the `◄ ►` arrows, whose columns are derived from the very string the
  row renders.

  **The footer now carries `[ Save (Ctrl+S) ]` and `[ Cancel (Ctrl+E) ]`**, flush right on the hint
  row, which is also where the `Ctrl+S` / `Ctrl+E` hints used to be spelled out — the
  buttons name both the action and its key, so repeating them only crowded the row. Save
  is the same code path as the key, including the typed confirmation on a booth with
  hand-written files: a button must not become a way around that guard. Cancel asks
  first, and asks *in place* — the pair becomes `[ Discard (ENTER) ]` and `[ Back (ESC) ]`,
  so the mouse that raised the question can answer it instead of sending the user to the
  keyboard mid-gesture, and while it stands a click anywhere else is ignored so a stray
  one cannot discard a configuration. Clicking Save mid-edit commits what was typed
  rather than saving the state from before it. Too narrow a terminal drops the buttons
  rather than drawing them somewhere wrong; the keys are unaffected.

  **Cancel only asks when there is something to lose.** Closing a booth you only
  opened to look at used to cost a confirmation about discarding nothing. Whether there
  is anything to discard is answered by comparing the editable state — selections, param
  values, config fields — against a snapshot taken when the TUI opened, *after* `--select`
  and the other flags were applied, so pre-filled values are not counted as the user's
  edits. A `dirty` flag flipped at each mutation was the obvious alternative and the wrong
  one: every future handler would have to remember it, and the one that forgot would make
  the TUI lie about unsaved work. Comparing cannot forget, and it buys a property a flag
  could not — selecting a template and deselecting it again is genuinely no change, so it
  does not ask. A half-typed value has not reached the maps yet, so it counts as unsaved
  on its own.

  That uncovered a gap while wiring it: `Ctrl+S` and `Ctrl+E` were **swallowed inside
  every text field** — they fell through to the "insert a character" branch, so the only
  ways out of an edit were Enter and Esc, even though the footer buttons beside them
  worked. Both keys now reach their handlers from inside an edit, whatever the cursor
  resolves to: Ctrl+S commits what was typed and saves, Ctrl+E weighs it and asks.

  Where a click and a keypress mean the same thing they now *are* the same thing:
  `activateConfigRow` is what Space does to a config row, `stepSuggest` is what the arrow
  keys do to a suggested value, and both are called from the mouse — so neither input can
  drift into meaning something the other does not. Deliberate asymmetries: clicking a
  **row** only moves the cursor while clicking its `[ ]` **marker** selects, so reading a
  description cannot silently change a selection; clicking away from an edit **keeps**
  what was typed, as Enter would, rather than stranding the TUI in edit mode with the
  next keystroke going somewhere invisible; the startup warning dismisses on a click, but
  the overwrite confirmation ignores the mouse entirely, because it exists to make
  destroying hand-written files cost more than a reflex.

  **The trade, stated up front:** owning the mouse costs the terminal's own click-drag
  text selection, so the footer says so on open and points at Shift+drag. Verified in a
  real terminal by writing SGR mouse sequences (`ESC[<0;x;yM` — byte-identical to a real
  click, since the TUI requests `1006`) into a PTY: a booth selected, its package list
  filled and its `GO_VERSION` stepped from `1.25.7` to `1.25.0` by clicks alone, then
  saved and read back from the generated Boothfile. VHS has no mouse, which is why the
  proof is a PTY. 22 unit tests cover the rest, several asserting against `View()` itself
  so that adding a header line breaks the row map loudly instead of shifting every click
  by one.

- **You could not paste into the config TUI, and nothing said so.** Reported against
  `go-pkg`'s package field, where the value being typed is a module path copied from a
  browser — the worst possible thing to retype. Every text field tested
  `len(msg.String()) == 1` before accepting a character, and a paste is not one character:
  Bubble Tea enables bracketed paste by default, so the clipboard arrives as a single
  `KeyRunes` message whose `String()` is deliberately wrapped in `[...]` (so key bindings
  cannot match a paste). Both halves of the test failed and the paste was dropped silently.
  Driving the real TUI through a PTY found a second shape with the same fate: Bubble Tea
  coalesces "the longest sequence of runes that are not control characters" from one read
  into **one** `KeyRunes` with no paste flag, so a terminal without bracketed paste, an
  `xdotool type`, a laggy link, or a multi-rune IME commit also lost everything but nothing.
  One `typedText` helper now answers "what text does this key contribute" for all six input
  sites — search bar, config string/int/list fields, single-value params, variadic package
  rows, and the overwrite confirmation — and the payload is filtered to printable ASCII, so
  the newline that comes with a copied *line* cannot end up inside a Boothfile value. Int
  fields keep filtering per character, so a pasted `30 minutes` still becomes `30` rather
  than a `config.toml` that will not decode. Pasting `gopls@latest,dlv@latest` into one
  package row yields two rows, which falls out of the comma-joined storage. Verified in a
  real terminal: a bracketed paste written to a PTY in one chunk lands in `GO_PKGS` and saves
  as `arg GO_PKGS=golang.org/x/tools/gopls@v0.16.1`.

- **Every package-install page now shows how to write a version — and how to write one
  without.** `go-pkg` and its 18 siblings offered a `*_PKGS` field with no hint of the syntax
  it expects, and that syntax is not shared: `@` for npm/bun/yarn/deno/code-extension (their
  own), `@` for cargo/dotnet/hex/luarocks (a CodingBooth convention the install script
  rewrites into `--version`), `==` for pip/uv, `=` for conda/apt, `:` for gem, `-` for
  cabal/pecl, `/` for conan. Each page's description now ends with the two forms side by side
  (`ripgrep`, or `ripgrep@14.1.0`) — last, so they stay on screen when the panel scrolls to
  keep the focused field visible. The three pages with no unversioned form say so plainly:
  `go install` refuses a bare module path (so the floating form is `@latest`), a Conan
  reference *is* name plus version, and `deno add` needs an `npm:`/`jsr:` prefix. Written from
  an audit of what each `*--install.sh` actually runs, not from the manager's documentation.

- **`install pecl redis-6.0.2` could never have worked.** The documented `-version` pin fed
  the whole spec back as the shared-object and ini basename, so pecl built `redis.so` while
  the script demanded `redis-6.0.2.so` and failed the image on its own post-install check.
  It now strips a suffix that looks like a version or a PECL state tag (`-6.0.2`, `-beta`)
  for those names only, leaving a name that merely contains a hyphen alone; the `.so` check
  stays, so a wrong guess still fails loudly instead of installing something unloaded.
  `tests/setups/test--pecl-install.sh` pins both directions with a stubbed `pecl`.

## 0.67.0

- **The PlantUML server never worked — it answered `503` forever, and the icon made that
  visible.** Reported as "PlantUML does not start when I click", and the click was not the
  problem: `start-plantuml` bound its port in ~1s, so `cb-web-open`'s liveness check passed
  and it opened a browser onto an app that was not there. The war never deployed. Established
  by measurement, not reading — every combination was timed to first `HTTP 200`:

  | attempt | result |
  |---|---|
  | `jetty-runner` 12.0.16 (as shipped) | 503 forever |
  | `jetty-ee10` / `ee9` / `ee8` runner 12.0.16 | 503 forever |
  | `jetty-home` 12.0.16 + ee9 modules | 503 forever |
  | `jetty-runner` 11.0.24 | deploys, renders SVG, JSP editor dies: *No InstanceManager set* |
  | **`jetty-home` 11.0.24 + `jsp` module** | **HTTP 200 in ~2s, Monaco editor, renders** ✅ |

  Two things were wrong at once. The war is `web-app 5.0` (Jakarta EE 9), which is **Jetty 11**
  natively — Jetty 12's "ee9" is a compatibility layer, not the same thing. And `jetty-runner`
  cannot supply the Jasper `InstanceManager` the editor's JSPs need, so even on 11 it served
  diagrams but not the UI; the full distribution's `jsp` module does. Jetty's own errors were
  invisible throughout because the war ships no SLF4J provider, so deployment failures went to a
  NOP logger — the diagnosis needed one bolted on. PlantUML's built-in `-picoweb` was evaluated
  and rejected: it renders correctly but exposes only a rendering API, so adopting it would have
  quietly traded the editor away. Verified end to end through the edited setup: click → start →
  `HTTP 200` in ~1s → `<title>PlantUML Server</title>` → SVG renders.

- **Web-app launchers now carry the app's own artwork instead of a generic globe.** `cb-web-icon`
  treats an `--icon` that names an existing *file* as artwork: it copies it to
  `/usr/share/codingbooth/icons/<id>.<ext>` and references it by absolute path (which the
  desktop-entry spec allows, and the Jupyter launcher already did). The copy is the point — the
  source often sits in a build tree a later cleanup deletes, and an `Icon=` pointing at a deleted
  file renders blank. Each setup picks its own: **Excalidraw** takes upstream's `favicon.svg`
  (scalable, preferred over the raster candidates), **Scratch** its `favicon.ico`, and **PlantUML**
  has its favicon extracted from the war with `unzip`. Every one falls back to a themed icon
  (`x-office-drawing`, `applications-education`, `applications-graphics`) if the layout ever
  shifts, so a missing asset can never fail an install. **Mermaid** keeps a themed icon by design:
  its editor page is authored by the setup rather than taken from a Mermaid build, so there is no
  upstream mark to borrow.

- **viewmd gets a desktop icon, and starts on click.** Registered from a new
  `viewmd-desktop-icon--setup.sh` rather than from `viewmd--setup.sh`, because of *when* each runs:
  viewmd is installed into the **base** image, where no desktop exists, so `cb-web-icon` would
  correctly no-op there and the icon would never reach any variant. The four desktop Dockerfiles run
  the new setup after their DE is in place. It also installs `start-viewmd`, which serves the
  project mount (`/home/coder/code`, falling back to `$HOME` when a booth has no code directory) on
  viewmd's own port 8765. Verified in a desktop image: descriptor, launcher, `/etc/skel/Desktop`
  entry, and a simulated click on a stopped service returning `HTTP 200`.

  Worth stating plainly, since it prompted the question: **click-to-start already worked** for every
  web launcher. `cb-web-open` checks the port, runs `START_CMD` when nothing is listening, waits for
  it, then opens the browser — confirmed against a stopped service. Nothing needed changing;
  PlantUML only looked like a click problem because it started and then served 503.

- **Desktop icons now start at the top-left and grow right, not from the centre.** Centring
  re-derived the starting column from the number of launchers, so *every* icon shifted whenever one
  was added or removed and nothing kept a stable position between booths. The row now starts at a
  fixed column 1 — column 0 stays reserved for xfdesktop's own Trash / Filesystem / Home — and
  appends rightwards, wrapping to column 1 of the next row. Verified by running the arrangement
  script against a mocked X server: launchers land at columns 1,2,3…; a 12-icon narrow screen wraps
  to row 1 col 1 and never collides with column 0; and adding a launcher leaves the existing ones
  exactly where they were. Note the arrangement is one-shot per home (a marker file preserves manual
  re-arrangement), so an existing booth keeps its current layout.

  `tests/config/test90` covers viewmd now too (7 services). Extending it surfaced a flaw in the
  guard itself: it located the registration with an unanchored `grep`, which matched
  `cb-web-icon.sh` in a *comment* rather than the call, and the new setup — which explains itself in
  its header — was the first file to expose it. Now anchored to the start of a line.

- **One flaky test cost a 28-minute re-run of 116 that had nothing wrong with them.** The release
  pipeline's `integration-tests` was a single job running three suites as sequential steps, so any
  failure meant re-running all of it. That is not hypothetical: the 0.67.0 run failed with
  **115/116 complex tests passing**, the one casualty being `test-boothfile-bash-nb-kernel`, whose
  image build died on `git clone https://github.com/pyenv/pyenv.git` returning **HTTP 503**. It is
  the norm, not the exception — every recorded failure of this stage is the same shape: runs
  `30166469987` and `30149483477` (`test-boothfile-grok`), `28998933234` (`test-boothfile-mkcert`),
  `28282865658` (`test-boothfile-build-essential`), and `29706988370`, which took out six tests at
  once. Scanning those logs for causes turns up **only** 429/502/503 — not one logic failure in the
  set.

  So the job is now **three jobs** — `go-integration-tests`, `basic-tests`, and `complex-tests`
  sharded four ways — and "Re-run failed jobs" re-runs only what broke. The complex suite is ~23min
  of the ~28min total, so it is the only part worth sharding; the other two are 33s and 87s. Shards
  are round-robin over the sorted test list, which needs no per-test timing table to maintain and
  measures out at 8.5/5.5/4.9/4.2 min against the 0.67.0 run's real durations. `fail-fast: false`
  keeps a failing shard from cancelling its siblings — otherwise the re-run tells you nothing about
  the tests that were killed mid-flight. Wall clock drops from ~28min to ~11min, and the price of a
  flake drops from 28min to one shard.

  `run-complex-tests.sh` grew the selection to make that possible: `--shard N/M`, explicit test
  names, `--list`, and `--no-retry`. A failing run now prints the exact command to re-run just the
  failures. `tests/config/test91` guards the part that can silently rot — that shards are an **exact
  partition** at 2/3/4/5/8 shards wide, since a test that lands in no shard is never run and CI
  stays green while covering less than it claims — plus balance and every rejection path, because a
  typo in the CI matrix silently reinterpreted as "run everything" would be worse than an error.

  **On the flakiness itself**, two changes. The runner now retries a failed test **once, and only
  when its output matches a transient-network signature** (429/502/503/504, rate limit, connection
  reset, DNS failure, TLS timeout). A real assertion failure still fails on the first attempt — this
  buys reliability without the usual cost of blanket retries, which is that genuine bugs get papered
  over. Retries are counted and reported even on a green run, so a suite that only stays green by
  retrying says so out loud. And the actual 503 got fixed at the source: **seven `git clone` calls
  across six setups had no retry at all** — `python` (the pyenv clone that broke 0.67.0), `ruby`,
  `jenv`, `kubectx`, `excalidraw` and `scratch`. Each now retries three times with backoff, clearing
  the partial clone first, since git refuses to clone into a non-empty directory. Verified against a
  stub `git` under `set -Eeuo pipefail` with an `ERR` trap: transient-then-success exits 0 without
  tripping the trap, and a persistent failure still exits 1 with a clear message.

  Not addressed here, and worth a decision: **89 of the 97 setups that use `curl` pass no `--retry`
  at all** (`mkcert` is the model, with `--retry-all-errors` and a pinned fallback). The runner-level
  retry covers them in CI, but nothing covers a user's own build. Related: the 429s specifically come
  from the unauthenticated GitHub API budget being shared per runner IP and exhausted mid-sweep;
  passing a token via BuildKit secrets would raise it from 60/hr to 5000/hr, but that puts a
  credential into the image build path and needs deciding rather than defaulting.

- **Half the web-UI tools never got the desktop icon the feature promised.** `cb-web-icon` landed
  wired into exactly three setups — Jupyter Notebook, CloudBeaver and Scratch — and the other three
  web servers in the catalog were simply never hooked up. **Excalidraw**, **Mermaid** and
  **PlantUML** each installed a `start-<name>` launcher and served an HTTP UI, but on the desktop
  variants nothing pointed at them: no icon, no waybar button, and no `/etc/cb-web-services`
  descriptor at all. Only someone who already knew the starter name could reach them. Excalidraw is
  the sharpest case, since it is a near-clone of `scratch--setup.sh` — which registers its icon
  correctly — so the omission was a copy that stopped one line short. All three now register a
  launcher the same way. Verified by running the three registrations against a stock
  `desktop-xfce` image: each writes its descriptor, its `/usr/share/applications/<id>-web.desktop`,
  and lands in the `/etc/skel/Desktop` registry alongside the app icons.

  What let it slip is that **nothing tested this path** — no test anywhere referenced `cb-web-icon`
  or `cb-web-open`, so three missing icons cost nothing. `tests/config/test90` closes that, and it
  *derives* the set it checks rather than listing it: a setup that installs a
  `/usr/local/bin/start-<name>` and documents an `http://localhost:` URL is a web-UI server and
  must register an icon, minus the desktop environments themselves (XFCE, KDE, LXQt, Wayland),
  which match the shape but host the icons rather than needing one. So the next web tool added is
  covered on arrival instead of waiting for someone to notice. It also asserts each icon's
  `--start` names the starter that same setup installs — an icon that launches a command nothing
  provides is worse than no icon — that ids stay unique, since they key
  `/etc/cb-web-services/<id>.conf` and a collision would silently overwrite a descriptor, and that
  the derivation still finds at least six services, so a rename cannot quietly empty the candidate
  list and turn the whole guard into a no-op that always passes. Confirmed to fail by removing the
  Excalidraw registration again.

- **The wrapper test suite could not run on a Mac, and nothing ran it anywhere else.** All 21
  non-DinD tests in `tests/wrapper/` died in the shared helper with `privileged[@]: unbound
  variable` — bash 3.2, which is what macOS ships as `/bin/bash`, treats `"${empty[@]}"` as unset
  under `set -u`, so `run_in_container` aborted before reaching docker. `_lib.sh` now uses the
  `${arr[@]+"${arr[@]}"}` guard already used in ten other places in the tree. With that fixed the
  suite is wired into CI: a new `wrapper-tests.yaml` workflow builds the test image (Buildx with a
  GitHub Actions layer cache) and runs the suite on any push or PR touching `booth` or
  `tests/wrapper/**` — the first workflow in the repo that runs tests at all. `080-public-install`
  is held out of it, because it measures what is deployed at codingbooth.io rather than the
  checkout and so can go red for reasons no commit here caused; `run-all.sh` gained the
  `--include-public` opt-in its own test headers had always documented but nothing implemented.
  Naming a public test by number still runs it. That test was itself failing, and had been since
  `7fbab00d` slimmed the wrapper in May: it asserted two lines that commit deleted — the
  pipe-install banner, which the published `install.sh` cannot reach because it fetches the wrapper
  with `curl -o` rather than piping it, and a `✅ CodingBooth has been installed.` banner that no
  longer exists anywhere. Both are replaced by assertions on what the flow prints now, including
  the `shell-config` step that nothing checked. The full suite is 22/22 with `--include-public`.

- **`install apt` could not install anything on Apple Silicon once `booth config` stamped a
  snapshot.** `apt-example` and `systemlib-example` both failed with `E: Unable to locate package`
  for packages that plainly exist — `ripgrep`, `sqlite3`, `libcurl4-openssl-dev` — right after an
  `apt-get update` that had just downloaded the very index listing them. The cause is that Ubuntu's
  snapshot service only mirrors the primary archive: `apt-config dump` maps
  `archive.ubuntu.com`/`security.ubuntu.com` to `snapshot.ubuntu.com`, has no entry for
  `ports.ubuntu.com`, and `snapshot.ubuntu.com/ubuntu-ports/<id>` answers 401. On arm64 — which is
  every Mac build — apt therefore ignored `--snapshot` while *updating* (fetching the live ports
  lists, hence the reassuring output) and then honored it while *installing*, resolving against a
  snapshot index that was never populated. Anything already in dpkg's state still "installed", so
  the failure looked arbitrary: `jq` and `tree` passed, `ripgrep` did not. `apt--install.sh` now
  passes `--snapshot` only on amd64/i386 and elsewhere prints a warning and resolves against the
  live archive, so arm64 builds work and lose the freeze loudly instead of breaking. Verified both
  directions against the real base image: on arm64 the warning appears and `ripgrep` installs, on
  `--platform linux/amd64` the `🧊 Pinning` line still appears and the fetch still comes from the
  snapshot service. The complex test that should have caught this installed only `jq` — preinstalled
  in the base image, so it resolved from dpkg regardless of the pin; it now also installs `ripgrep`,
  which can only come from the archive. Documented as an amd64/i386-only guarantee in
  REPRODUCIBILITY.md (a Mac-built booth is Tier 1 for apt, not Tier 2) and in BOOTH_INSTALL_APT.md.

- **`booth install` reported "already installed" even when the binary was missing.** The install
  path short-circuited on the mere presence of the lock file, so a project whose lock pointed at a
  version that was no longer in the cache (cleared cache, fresh checkout of a tree that commits the
  lock) got *"CodingBooth is already installed … use update"* — while `booth version` for the same
  project correctly reported `(binary missing)` and a plain `booth <cmd>` auto-downloaded it. Only
  `install` was fooled. It now mirrors the run-mode auto-download: it checks `find_binary_dir` for
  the pinned version/platform and only claims "already installed" when the binary is actually
  present; otherwise it downloads the pinned version (honoring the lock's cache mode) instead of
  telling the user to run `update`. Verified end to end on macOS — install, nuke the cached
  version, `booth install` now re-fetches it; and re-running with the binary present still
  short-circuits without downloading. `tests/wrapper/014-install-when-binary-missing.sh` pins the
  new path; `011-install-idempotent.sh` still guards the already-installed case.

## 0.66.0

- **The force-push guard only ever blocked one of the four ways to force-push.** Accept Edits denied
  `git push --force*` in both flag positions and stopped there, so `git push -f` — the spelling
  most people actually type — went straight through. Confirmed in a booth rather than reasoned
  about, using `git reset --hard` as a control: that came back `PERMISSION-BLOCKED` while
  `git push -f nosuchremote master` came back `RAN`, failing only because the remote did not
  exist. The same probe turned up a fourth spelling nothing covered: `git push origin +master`
  forces via the refspec's `+` prefix, with no flag for a pattern to match. The list now pins all
  four, each in both positions, since a flag trails the remote as readily as it precedes it.
  Re-verified end to end: `-f` before and after the remote, `+refspec` with and without a remote,
  all blocked — and a plain `git push origin master` still runs, so the added patterns do not
  catch ordinary pushes. `tests/config/test89` asserts each rule. Note this leaves
  `--force-with-lease` denied along with the rest: it is the *safe* rewrite, and deny beats allow
  in Claude Code, so permitting it means narrowing the `--force*` pattern rather than adding an
  allow entry — worth deciding deliberately rather than by accident.

- **Accept Edits stopped blocking `curl … | bash`, which is how CodingBooth itself is installed.**
  The seeded deny list carried `curl *|bash*`, `wget *|bash*`, both spaced variants, and
  `chmod 777 *`. They read like safety rules; they were not. `Bash` is on the allow list, so
  `curl -o /tmp/i.sh URL && bash /tmp/i.sh` was never blocked, and `chmod 777 *` does not match
  `chmod -R 777 .` — the rules blocked a *spelling*, not a capability, and anything willing to
  use a different one walked straight past. Nor were they catching accidents: nobody pipes a
  remote script to a shell by mistake. What they did reliably block was the project's own
  documentation — `AGENT_SETUP.md` installs the booth wrapper with `curl -fsSL … | bash`, and
  `AGENT.md`'s setup-script template opens with the same line, so an agent following either got
  a refusal. (The `What NOT to Do` row naming `curl | bash` is about *persistence*, not safety:
  every other row in that table is, and the sentence after it explicitly permits ephemeral
  installs for experimentation.) Removed from all four copies of the list — the template plus
  the `blog`, `elixir-example` and `playground4` booths that carry hand-written duplicates.
  What stays is the part that earns its place: the git working-tree destroyers and the `rm -rf`
  guards are **anti-accident, not anti-adversary**. An agent reaching for `git reset --hard` to
  tidy up is a real failure mode, and the rule catches the spelling it actually uses. Removing
  the last entry of a list also leaves the one above it holding a comma, which would ship a
  `settings.json` Claude Code cannot parse — it nearly did here — so `tests/config/test89` now
  asserts the generated file is valid JSON, verified by reintroducing the comma.

- **A booth no longer asks whether you trust your own project, every single start.** Claude Code
  gates a folder behind "Quick safety check: Is this a project you created or one you trust?"
  before it will work in it. That gate is not a permission rule, so nothing in the Accept Edits
  allow list could ever have suppressed it — it is project state, recorded per path in
  `~/.claude.json` as `projects[<dir>].hasTrustDialogAccepted`. The settings cache persists
  `~/.claude/`, a *directory*; `.claude.json` is a file sitting beside it, outside the mount. So
  every start reseeded it from the host, whose copy records trust for host paths and has never
  heard of `/home/coder/code`: the booth's own "yes, I trust this folder" was written and then
  dropped at shutdown, and the prompt came back forever. The Accept Edits startup segment now
  stamps the flag into the seeded copy, beside the `jq` patch that already injects `rm -rf` deny
  rules for detected mounts — the same seed-then-amend shape, pointed at a second file. Stamped at
  run time rather than shipped in the seeded content because the path isn't knowable earlier:
  `CODE_NAME` can move the code directory, so the segment takes it from its own cwd. It steps
  aside when `~/.claude.json` is a bind mount, because then `cache/` or `shared/` owns the file and
  a persisted copy already carries the answer. Deliberately narrow: no `permissions.defaultMode` —
  the existing allow list already suppresses the prompts it covers (verified: `Bash` runs
  unprompted inside a booth), so setting a mode would change behaviour that works.
  `tests/config/test89` guards the emitted script and
  `tests/complex/test-claude-code-trust-stamp` guards the runtime result, including the
  step-aside; both verified by reintroducing the regression.

- **The Accept Edits extension no longer opens every session with a warning modal.** Its seeded
  `.claude/settings.json` listed `"mcp__*"` under `permissions.allow`, which Claude Code rejects —
  a glob is permitted only in the tool position, after a literal `mcp__<server>__` prefix. The rule
  therefore never allowed anything, and worse, it raised a blocking "Settings Warning" prompt that
  had to be dismissed on *every* launch before the session could start: an extension whose whole
  purpose is removing friction was adding a keystroke to each run. Dropped, with the reason
  recorded in the template — allowing an MCP server means naming it. The rule had been hand-copied
  into two other settings files, `blog/.booth/` and the shipped `elixir-example` workspace, so
  `booth example try elixir` handed every new user the same modal; both got the same fix. The
  second copy only surfaced because `tests/config/test89` asserts repo-wide rather than only on
  what it generates — worth remembering the next time a rule is duplicated by hand. Deny and ask
  rules accept wildcards anywhere, so the deny list is untouched.

- **Seeded credentials are now readable by the booth user.** Selecting `claude-code` auto-selects
  both its credential extension (which drops `~/.claude/.credentials.json` in through
  `/etc/cb-home`) and its settings cache (which bind-mounts `~/.claude` from `.booth/cache/`).
  booth-entry's copy runs as root, so the credential landed `root:root 0600` — and its blanket
  ownership sweep, `find "$HOME_DIR" -xdev -user root`, stops at the boundary of that bind mount
  and never reached it. The mount was present and the file was there, but `claude` runs as
  `coder` and got "Permission denied" reading its own credentials, so every booth fell back to
  an interactive login. booth-entry now hands over ownership of exactly what each seed/override
  layer copied, walking the *source* tree so the cost tracks the size of the layer rather than
  whatever the cache has accumulated. The same defect silently applied to `gemini-cli`, `goose`,
  `grok`, `oh-my-pi` and `opencode`, whose credential seeds also target a directory their own
  settings-cache extension mounts. `tests/complex/test-claude-code-credential-ownership` guards
  it; the existing `test-claude-code-credential-cache` could not, because it pre-creates the
  cached credential file on the host and `cp` over an existing file keeps that file's owner.
  `claude-code--setup.sh` also stopped advertising the old `~/.claude:/etc/cb-home-seed/.claude`
  recipe, which seeds session history along with the credential and, being no-clobber, loses a
  refreshed host token to the stale cached copy.
- **Booths started at the same time no longer fight over the same port.** Port selection was
  check-then-use: `isPortFree` bound the port, closed it immediately, and handed the number
  back — then `docker run -p 127.0.0.1:<port>` claimed it seconds later, after name
  resolution, sidecar startup and manifest writes had each made their own docker calls. And
  the default port spec is `NEXT`, which hands every caller the *first* free slot, so two
  booths starting together were not merely at risk of picking the same number, they were
  steered onto it. The loser died with `Bind for 127.0.0.1:11000 failed: port is already
  allocated` — exit 125 and no output whatsoever, which is why this had only ever been seen
  from the outside as booths intermittently returning nothing under a parallel test run.
  Measured on this machine, eight booths started simultaneously: **6 of 8 failed**.
  The fix is in two parts, because one alone is not enough. The socket found during the scan
  is now *held* rather than closed, so the port stays genuinely busy while the booth prepares
  (6/8 → 2-3/8). It cannot cover the rest: docker has to bind the port, so the listener must
  be released before `docker run`, and that call takes ~200ms to reach the networking step —
  a window another booth can still scan through. So the chosen port is also recorded as a
  claim file under `<tmp>/codingbooth-ports/`, which other booths consult during their own
  scan and which is dropped once the container is up. A claim older than 60s is ignored, so a
  booth killed mid-launch parks a port for a minute at most, and an unusable claim directory
  degrades to the held-socket behaviour instead of refusing to start. Eight and sixteen
  booths started simultaneously now succeed on distinct ports, **0 failures** across four
  runs. An explicit `--port` is untouched: it is a contract, so a conflict there still fails
  loudly rather than quietly moving.

- **`test-boothfile-aws-cdk` was failing on output that matched.** The test greps `cdk --help`
  for `synth|deploy`; both words are right there in the output it printed on failure. The bug
  was the plumbing: `echo "$VAR" | grep -q PATTERN` under `set -o pipefail`. `grep -q` exits at
  the first match, bash's `echo` builtin writes in buffer-sized chunks, and the write after the
  pipe closes takes SIGPIPE — so the pipeline reports 141 and the `if` takes the else branch
  even though the text matched. It is purely a function of payload size: measured at 4KB it
  never fires, at 60KB it always does, and `cdk --help` is 10,564 bytes — right in the
  coin-flip band, 16 spurious failures in 40 runs. Matching with a here-string instead has no
  writer process to kill. Of the 318 other `echo "$X" | grep -q` sites in the suite this was
  the only one grepping an untruncated multi-KB dump; the rest compare small captures, and
  `grok`/`herdr` — the only other tests reading a full `--help` — pipe through `head` first.

- **Every booth can now read its own Markdown.** `viewmd`
  ([MarkDownViewer](https://github.com/NawaMan/MarkDownViewer)) is installed into the base
  image by `variants/base/setups/viewmd--setup.sh`, so all variants inherit it — a single Go
  binary that serves a folder of `*.md` files to a browser with a file tree and GitHub-flavoured
  rendering. It already knows about booths: `viewmd --md README.md --expose` calls
  `booth--expose` itself, so the page is reachable from the host without any extra wiring. The
  setup script follows the usual shape — `--version <X.Y.Z>|latest`, defaulting to `latest` with
  a pinned fallback when the rate-limited GitHub API cannot answer — and additionally verifies
  the downloaded binary against the release's `SHA256SUMS`, failing the build on a mismatch. It
  is listed in the login welcome message next to `editor` and `explorer`, because a tool nobody
  is told about is a tool nobody uses. `tests/basic/test016--viewmd.sh` guards all four
  properties: on PATH, runs, advertised in the welcome, and actually answers HTTP 200 for a
  served folder.

- **`setup gh <version>` now actually pins.** `gh--setup.sh` read `GH_VERSION="${1:-latest}"`
  on line 18 and never referenced it again — it unconditionally added the cli.github.com apt
  repo and ran `apt-get install -y gh`, so `setup gh 2.63.2` silently installed whatever the
  repo happened to be serving. A version argument now installs that exact release's `.deb`
  from `github.com/cli/cli/releases` (the apt repo only carries recent builds, so it cannot
  serve an older pin), while the default `latest` keeps the existing apt path byte-for-byte
  unchanged — `setup gh` with no argument behaves exactly as before, including in
  `tests/complex/test-boothfile-gh-copilot`. The script also accepts the `--version <ver>`
  flag form used by most other tool setups, and tolerates a leading `v`. `templates/tools/gh`
  now exposes the knob as `GH_VERSION`, so `booth config --select gh:2.97.0` reaches it —
  before, a working pin would still have been unreachable from the TUI.

- **The `cursor` template now has a setup script to call.** `templates/ai-tools/cursor`
  emitted `setup cursor`, but no `cursor--setup.sh` had ever existed — not in any variant, not
  anywhere in git history. Selecting Cursor scaffolded a Boothfile that failed the Boothfile
  compiler's name check and could never have built. `variants/base/setups/cursor--setup.sh`
  installs Cursor's official `.deb` (amd64 and arm64), resolved through
  `cursor.com/api/download`, and wraps `/usr/bin/cursor` with `--no-sandbox` the same way
  `antigravity--setup.sh` does, because Chromium's sandbox needs privileges a booth does not
  grant. The shipped `.desktop` entries are re-pointed at that wrapper, so launching from the
  desktop menu gets the same treatment as launching from a shell. Like Antigravity, it is
  skipped on non-desktop variants. Cursor's download URLs embed a build commit rather than a
  plain version, so there is no version to pin: `CURSOR_TRACK` selects the release track
  (`stable`, `latest`), and `--deb-url` takes one exact build for anyone who resolves it
  themselves. The credential extension now also seeds `~/.config/Cursor` (Linux, macOS and
  Windows paths) — Cursor is a VS Code fork whose sign-in lives there, so mounting only
  `~/.cursor` never kept a session.

- **No version named now means "the current release" for four more setups.** `elixir`, `exercism`,
  `kotlin` and `rescript` all *accepted* `latest` but defaulted to a constant that only moved when
  someone remembered to bump it; they now default to `latest` in both the setup script and the
  template. Two others were examined and deliberately left pinned: `elm`, because npm's `latest`
  dist-tag for it points at the prerelease `0.19.2-0`, and `scala`, because `lampepfl/dotty` marks
  its LTS line as the GitHub "latest release", so tracking it would *downgrade* the default from
  3.5.1 to 3.3.8. Both reasons are recorded in
  [`EXAMPLES.md`](../EXAMPLES.md#known-imperfections) rather than left for the next person to
  rediscover.

- **Resolving `latest` no longer fails a build when the GitHub API is unreachable.** `elixir`,
  `exercism` and `kotlin` called `api.github.com` and exited non-zero if it returned nothing —
  and unauthenticated calls are rate-limited to 60/hour per IP, so a busy CI host could break a
  build that had merely declined to name a version. They now warn and fall back to their pinned
  constant. The other `latest`-resolving setups still fail hard; that is pre-existing and is
  written down as a known imperfection rather than quietly fixed everywhere.

- **`EXAMPLES.md` gained a Known Imperfections section.** Nine limitations stated plainly instead
  of smoothed over: that `latest` and reproducibility are in genuine tension and only an image
  digest resolves it; the 18 setups whose default cannot track upstream at all; that a setup's
  default and its template's default are separate values that already disagree (`go` 1.25.3 vs
  1.25.7, `jdk` 21 vs 25, `nodejs` 20 vs 22) with nothing keeping them in sync; that `latest` puts
  a rate-limited network call on the build path; that apt version pins are ephemeral; that all 41
  VS Code extension setups and 14 of 17 notebook kernels have no version knob at all; and that
  `mvn`'s frozen default has already fallen off Apache's primary CDN.

- **Every setup that accepts a version now has a template that passes one.** 27 templates gained a
  version parameter, closing the gap where a working `--version` flag was unreachable from
  `booth config` and the TUI: `aider`, `ansible`, `aws-cdk`, `aws-cli`, `aws-sam-cli`, `azure-cli`,
  `claude-code`, `clojure`, `cmake`, `codex`, `fpc`, `gcloud`, `gradle`, `haskell`, `helm`,
  `kubectl`, `lazydocker`, `lazygit`, `make`, `mongodb`, `ollama`, `postgresql`, `pulumi`, `redis`,
  `sbt`, `terraform` — so `booth config --select terraform:1.9.8` now reaches
  `setup terraform --version 1.9.8`. Where the setup resolves `latest` at build time the parameter
  defaults to `latest`, so an unspecified version still means "current release" rather than a pin
  that ages. Four setups are deliberately left out, each for a stated reason (`firebase`'s
  `--node-version` is not a Firebase version; the desktop templates' knob is the Python template's;
  `dotnet`'s channel and SDK version are either/or; the conda extension's name would collide) —
  see [`EXAMPLES.md`](../EXAMPLES.md#reaching-the-knob-from-booth-config).

- **`latest` is now a valid version for four apt-backed setups.** `fpc`, `postgresql` and `gcloud`
  built the value straight into a package name, so `--version latest` would have asked apt for
  `postgresql-latest` or the pin `google-cloud-cli=latest` and failed; it now means the same thing as
  passing nothing — whatever the repo currently serves. `make` gained `--version apt` (and `latest`)
  as a synonym for `--from-apt`, so the distro build and a pinned from-source build are sayable
  through one knob instead of two mutually exclusive flags. Passing a concrete version to any of the
  four behaves exactly as before.

- **Selecting `gh-copilot` no longer silently unpins `gh`.** Its Boothfile segment emitted
  `setup gh` on top of the `requires = ["gh"]` that already pulls the GitHub CLI template in. With
  `GH_VERSION` now exposed that duplicate was actively harmful: the generated Boothfile ran
  `setup gh --version 2.97.0` and then a bare `setup gh` immediately after, so the second install
  overwrote the pinned one with whatever the apt repo served. The redundant line is gone; `requires`
  already guarantees it.

- **New guard: a template cannot name a setup that does not exist.**
  `tests/config/test86-all-setups-exist.sh` asserts that every `setup <name>` emitted by any
  template has a matching `variants/base/setups/<name>--setup.sh` — the mirror of test64, which
  already guarded the same thing for `install` backends. It is what the `cursor` gap needed:
  verified to fail on exactly that template with the script removed, and to pass with it in
  place (182 setup names checked).

- **New guard: a declared param cannot go unused.**
  `tests/config/test88-all-params-are-wired.sh` asserts that every `[params.X]` a template
  declares is referenced as `${X}` somewhere in that template's directory (directory, not file,
  because a parent may declare a param its extensions consume — `ollama` declares `OLLAMA_PORT`
  for its expose and autostart extensions). An unreferenced param is worse than a missing one:
  `booth config` shows the knob and writes `arg X=<value>` into the Boothfile, and nothing
  consumes it, so the user's choice is silently dropped. That is exactly the shape of a dropped
  `--version ${X_VERSION}`, and no other suite would notice. Verified by deleting the reference
  from `tools/gh` and watching test 117 fail; 152 params checked.

- **`cursor` and `gh` gained a config test.** `tests/config/test87-init-cursor-gh.sh` covers what
  the two fixes above actually produce: cursor's `CURSOR_TRACK` default and pin, its four
  credential mounts across the three host layouts, gh's `GH_VERSION` default and pin, and — the
  regression that prompted it — that selecting `gh-copilot` emits exactly one `setup gh`, the
  pinned one. Verified by restoring the duplicate `setup gh` and watching tests 13 and 15 fail.

- **New top-level [`EXAMPLES.md`](../EXAMPLES.md).** One page from a cold start to a running
  example: install, `booth example list`, `booth example try`, the full catalog grouped by
  kind, and a walk-through of `elixir`, `data`, and `kind`. It states plainly that the printed
  list is the authoritative one and that the document's copy is a snapshot. It also carries a
  survey of **which setups support version pinning** — exact pin, series-level pin, or no knob
  at all — including the setups whose working version argument no `template.toml` exposes yet
  (`helm`, `terraform`, `gradle`, the JetBrains IDEs, and ~20 more), so the gap is written
  down rather than rediscovered.

- **A select-DSL param value can hold a `/`, by quoting it.** A Go module path is
  nothing but slashes, and the DSL splits on `/` before anything else, so a package
  pinned through a param never survived the round trip: `booth config` on a booth
  carrying `arg GO_PKGS=github.com/pocketbase/pocketbase/examples/base@latest` died
  with `template "pocketbase" selected more than once` — the TUI writes pinned args
  back into the DSL, and re-parsing read the module path as one template per path
  segment. The documented CLI form was broken the same way
  (`--select go+go-pkg:google.golang.org/protobuf/cmd/protoc-gen-go@latest` selects
  templates named `protobuf`, `cmd` and `grpc`), as were scoped npm names and Conan
  `name/version` refs. Write such a value quoted — `--select
  'go+go-pkg:"github.com/user/tool@latest"'`, either quote character — and inside the
  quotes nothing separates anything: `/`, `~`, `+`, `,` and whitespace are all part of
  the value, at every level of the split, and the quotes are stripped at the leaves so
  nothing reaches the Boothfile wearing them. Only values that *need* quoting get it,
  so existing headers are byte-for-byte unchanged; `+` in particular is left alone,
  since it already stays with the value unless a letter follows it (`expose:+9000`,
  `apt-pkg:libstdc++6`). An unquoted `/` still splits — `go:1.25.7/claude-code` has
  the same shape and there it must — but the resolver now says so, adding a quoting
  hint to its "unknown template" and "selected more than once" errors when a param
  list was open earlier in the selection. Covered by
  `tests/config-tui/test18-tui-slash-pin.sh` (the TUI reopen+save path) and
  `tests/config/test85-select-quoted-param.sh` (the CLI form and the header round
  trip).

## 0.65.0

- **`setup`/`install` name validation now works outside the repo.** The Boothfile
  compiler learned the set of built-in script names by *scanning*
  `variants/base/setups/`, found by walking up from the binary or the cwd. That
  directory only exists in a checkout, so every booth run from a real project — the
  normal case — silently validated nothing: a typo'd `setup pyhton` produced no
  warning, just a build that failed later inside Docker. The list is now generated
  into `cli/src/pkg/boothfile/builtin-scripts.txt` by `build/gen-builtin-scripts.sh`
  (wired into `build/cli-build.sh`, so it cannot drift from what the base image
  ships) and embedded in the binary. Expect "Unknown setup script" / "Unknown install
  script" warnings — with a did-you-mean suggestion — in places that were previously
  quiet. Covered by `cli/src/pkg/boothfile/builtin_scripts_test.go`.

- **An empty package list is a no-op, not a build failure.** Every `*-pkg` template
  emits `install <manager> ${..._PKGS}` with the list defaulting to empty, so
  selecting `apt-pkg` (or `pip-pkg`, `code-ext-pkg`, …) in `booth config` without
  naming a package handed the install script zero arguments — and each one treated
  that as a usage error and killed the image build. All 17 `*--install.sh` scripts now
  report `ℹ️ No … requested; nothing to install.` and exit 0. Naming *nothing* is not
  the same as naming something broken: an unresolvable package or extension id is
  still a hard error. They also accept `-h`/`--help` explicitly, which is now the only
  way to get the usage text. `tests/setups/test--install-empty-args.sh` runs every
  `*--install.sh` in the directory, so a new manager is covered without editing it.

- **`GOBIN` is exported in Go booths.** `go--setup.sh` set `GOPATH` and put
  `$GOPATH/bin` on `PATH`, but left `GOBIN` unset. Tooling that reads the variable
  rather than scanning `PATH` — the VS Code Go extension, `go install` when re-run —
  therefore looked elsewhere, and packages installed by `install go` (the `go-pkg`
  template) were discoverable by path but not by that tooling. Same value as the
  `GOPATH/bin` default, now explicit. Asserted in `tests/complex/test-install-go/`,
  which already builds a Go booth, rather than paying for a separate image.

- **Wrapper `0.15.0` — `booth config` offers to install when the project has no
  binary yet.** Typing `booth config` in a folder (or under a parent) that has
  no `codingbooth.lock` used to either hard-error or — worse — open the TUI
  via a *foreign* wrapper that already had a lock (e.g.
  `../CodingBooth/booth config` from an empty project). The offer is keyed on
  **the project tree** (`$PWD` and parents: executable `./booth` *and*
  `codingbooth.lock` — a bare lock under e.g. `~/.booth` does not count), not
  on the invoked wrapper’s own lock. On a TTY: *Install and continue? [Y/n]* →
  install into `$PWD` (shared cache) and re-run `config`. Non-TTY with no
  usable binary still hard-errors. Only `config` gets the offer. Covered by
  `tests/wrapper/052-config-offer-install.sh`.

- **Every language now has a VS Code extension, and F# builds again.** A survey of all 32
  language templates found 24 with a curated extension and 8 without. crystal, elm, julia,
  nim, rescript, roc and swift now have one, each id verified present on **both** Open VSX
  and the Marketplace so a single `install_extensions` call covers code-server and desktop
  VS Code:

  | Language | Extension |
  |----------|-----------|
  | crystal  | `crystal-lang-tools.crystal-lang` |
  | elm      | `elmtooling.elm-ls-vscode` |
  | julia    | `julialang.language-julia` |
  | nim      | `nimsaem.nimvscode` |
  | rescript | `chenglou92.rescript-vscode` |
  | roc      | `IvanDemchenko.roc-lang-unofficial` |
  | swift    | `swiftlang.swift-vscode` |

  The eighth, **fsharp, had an extension that had never worked**: it emitted
  `setup code-extension ionide.ionide-fsharp`, and no `code-extension--setup.sh` exists.
  An unknown setup script is only a *warning*, so the `RUN` was emitted anyway and the
  build died at `code-extension--setup.sh: not found`. Being `auto-select = true`, that
  broke every `--select fsharp` from 48157fb4 until now. It gets a real
  `fsharp-code-extension--setup.sh` rather than the new `install code-extension` escape
  hatch, deliberately: that path is strict, and a strict install behind an auto-selected
  extension means one registry hiccup breaks every build touching the language.

  `roc` is the one language extension shipped **opt-in** (`auto-select = false`). Roc has
  no first-party extension and the only published one is third-party and self-described as
  unofficial — fine to offer, but a different proposition from making it the silent default
  the way rust-analyzer is.

  A fourth Marketplace-only id also turned up, `vscjava.vscode-lombok` (java), missed by the
  earlier audit because it sat behind a line continuation. Scoped to
  `install_vscode_extensions` like the other three; recorded in `docs/TODO.md`.

  Two data-driven tests now cover the whole catalog rather than a hand-picked list, so a new
  language extension is covered with no edit:
  - `tests/config/test84-init-language-code-extensions.sh` — 94 checks over all 31 language
    extensions: the setup script each one names exists, the selection compiles with no
    unknown-script warning, and the auto-select contract holds (roc opt-in, the rest on).
    This is the check that was missing; reintroducing the fsharp bug fails it on two counts.
  - `tests/setups/test--code-extension-setups.sh` — runs all 41 `*-code-extension--setup.sh`
    with both editor CLIs stubbed and asserts each exits 0 having installed at least one id.
    Catches the silent-no-op class the elixir and fsharp bugs both belonged to.

- **Any VS Code / code-server extension, by id (`install code-extension` /
  `code-ext-pkg`).** Editor extensions were curated-only: a language either had a
  `<lang>-code-extension--setup.sh` pinning one known-good id, or you were out of
  luck. There is now an escape hatch beside the curated set — name the marketplace
  id and it gets baked into the image:

  ```text
  setup codeserver
  install code-extension elixir-lsp.elixir-ls ms-python.python
  install code-extension eamodio.gitlens@15.6.0     # pinned
  ```

  or through `booth config`, via the new `code-ext-pkg` template (IDEs tab, beside
  `codeserver`): `--select "code-ext-pkg:eamodio.gitlens,esbenp.prettier-vscode"`. It
  compiles to Boothfile order 65 — the same slot as the curated `+vscode-ext`
  extensions, after the editor is installed — so the two mix freely
  (`elixir+vscode-ext/code-ext-pkg:eamodio.gitlens`). A trailing `@version` pins the
  release. The curated extensions remain the recommended path where one exists: a
  user shouldn't have to know an id to get a working editor.

  Extensions install into **every editor present**, not one: code-server and desktop
  VS Code keep separate extension trees and separate CLIs, and which one a booth has
  depends on its variant — code-server on the `codeserver` variant, desktop VS Code
  on all four desktop variants (each runs `vscode--setup.sh`). That is also why
  `code-ext-pkg` is a top-level template rather than an extension of `codeserver`:
  hanging it there would make a desktop-variant user install a second, browser-based
  editor just to name an extension.

  Unlike the curated setups, which log a warning and carry on, a bad id here
  **fails the build**. You named it explicitly, so a silent no-op would hand back an
  image quietly missing the extension you asked for — exactly the failure mode that
  hid the elixir bug below. The build also stops, with a message saying so, when no
  editor is in the image to install into. Failure modes are covered hermetically in
  `tests/setups/test--code-extension-install.sh` (12 checks, no build required) and
  end-to-end in `tests/complex/test-boothfile-code-extension/`.

- **The Elixir VS Code extension never installed — and the two editors don't share a
  registry.** `elixir-code-extension--setup.sh` asked for `JakeBecker.elixir-ls`, the
  *Microsoft Marketplace* id for ElixirLS. code-server resolves against Open VSX,
  where that id 404s. Because `install_extensions` logs a warning and returns
  success, the build passed and the booth came up with no Elixir support at all.

  Swapping in the Open VSX id (`elixir-lsp.elixir-ls`) fixes code-server and breaks
  the desktop variants, because there is no id that is right for both: on the
  Marketplace `elixir-lsp.elixir-ls` resolves to "ElixirLS Fork: **DEPRECATED**"
  v0.3.9999, a stub whose own description says to use `JakeBecker.elixir-ls`. So the
  wrong id there doesn't fail — it installs the wrong package.

  `libs/code-extension-source.sh` therefore gains two entry points beside the
  existing one, which is unchanged:

  ```bash
  install_extensions             mads-hartmann.bash-ide-vscode  # same id on both
  install_codeserver_extensions  elixir-lsp.elixir-ls           # Open VSX id
  install_vscode_extensions      JakeBecker.elixir-ls           # Marketplace id
  ```

  Each per-editor call is a quiet no-op when that editor isn't in the image, so they
  are safe on every variant. All 36 curated ids were then audited against **both**
  registries. Besides elixir, three are Marketplace-only and had been failing
  silently on code-server since they were written — `ms-dotnettools.csharp` (dotnet),
  `ms-vscode.cpptools` (gcc), `visualstudioexptteam.vscodeintellicode` (java). Those
  are now scoped with `install_vscode_extensions`, which makes the limitation
  explicit and drops a spurious warning from every code-server build; choosing Open
  VSX substitutes for code-server is left open in `docs/TODO.md`. Everything else
  differs only by ordinary version drift.

- **Booth call trace for the complex suite (`CB_DIAG_LOG`).** Complex tests capture
  booth with `2>/dev/null`, so a run that intermittently returns nothing left no
  evidence: the suite printed `FAILED:` with no output and there was nothing to
  diagnose from. `run_coding_booth` now records the command, its exit code, and a
  copy of stderr whenever `CB_DIAG_LOG` is set, and the complex runner points it at
  `tests/logs/complex-booth-calls.log` by default (`CB_DIAG_LOG=/dev/null` opts out).

  Stdout is deliberately left untouched — buffering it through a variable or a
  process substitution can itself drop output, which is the exact symptom under
  investigation, so only stderr is teed. The worst case is a few missing log lines,
  never missing test data. This is instrumentation, not a fix: booth occasionally
  returning nothing under full-suite load is still unexplained, and the intent is
  that the next occurrence explains itself rather than being retried away.

- **`test-env` now runs, and pins that a project-root `.env` is not imported.** The
  directory is `test-env/` but its script was named `test--workspace-env.sh`, and
  discovery expects `test--<dirname>.sh` — so it had never run since it was added in
  January, which only became visible once skipped tests started being reported. Its
  first assertion expected a project-root `.env` to be auto-loaded; that is not the
  design (only `.booth/.env` is, and it must be gitignored — a bare `.env` is often
  committed, sometimes with real values). The assertion is now inverted: it asserts
  the variable does **not** reach the container, so bare-`.env` auto-loading cannot
  be introduced silently. Use `env-file = ".env"` in `.booth/config.toml` to opt in.

  Its assertion harness was also broken — `[[ … ]] || fail` followed by an
  unconditional `pass`, so a failing check printed both ❌ and ✅ and the file
  reported four checks for three assertions. Each is now a plain `if/else`.

- **Test captures no longer lose booth's output to SIGPIPE.** `X=$(booth … | head -1)`
  under `set -o pipefail` let `head` close the pipe as soon as it had its line;
  booth took SIGPIPE, the pipeline went non-zero, and the capture collapsed to `""`.
  Where the call site had a `|| X=""` guard the test failed with an empty
  `Actual output:`; where it had none, `set -e` killed the script outright and the
  suite reported `FAILED:` with no output at all. It is a race, so it only landed on
  a loaded machine — which is why it read as flakiness for so long, and why
  `capture_codingbooth`'s retry papered over it instead of fixing it.

  All 66 affected call sites now capture booth's output first and apply the
  transform afterwards, and `capture_codingbooth` does the same internally, so its
  21 callers are covered too. `test-lifecycle`'s `grep -qx` probe got the same
  treatment — an early-exiting `grep` could turn a listed booth into a false
  negative. Consumers that drain stdin (`tail`, `tr`, `grep -v`, `grep -c`) were
  never affected and are unchanged. Regression test:
  `tests/dryrun/test028--capture-no-sigpipe.sh`, which forces the losing side of the
  race deterministically rather than waiting for load to expose it.

- **Six install managers were broken; the skipped tests had been hiding them.**
  - `install deno …` — Deno 2 requires `--global` to install a *command* (permission
    flags are global-only), so every `install deno` failed the build. The manager now
    supplies `--global` unless the caller already passed it (`--global` or a short
    bundle like `-Agf`). Project dependencies are unaffected — those go through
    `install deno-pkg`, which uses `deno add`.
  - `install luarocks …` — looked for luarocks under `/opt/lua-stable/bin`, but
    `setup lua` installs it from apt to `/usr/bin/luarocks`; no `/opt/lua-stable`
    exists at all, so the manager aborted every time. It now resolves luarocks from
    `PATH`, still honouring `LUA_HOME` when that really holds one.
  - `install pecl …` — `setup php` never installed `php-pear`, so no `pecl` binary
    existed; the setup's own `command -v pecl || true` swallowed it and advertised
    pecl anyway. `php-pear` is now part of the package set.
  - `install cabal …` — installed as root with cabal's default symlink method, so
    `/usr/local/bin/<tool>` pointed into `/root/.local/state/cabal/store/…`, which is
    unreadable for the `coder` user the booth runs as — the tool appeared as a
    dangling symlink. Now uses `--install-method=copy`.
  - `install conan …` — downloaded into root's `/root/.conan2`, invisible to `coder`,
    so the cache always looked empty. Now downloads as `coder`, and a failed download
    fails the build instead of being swallowed by `|| true`.
  - `install bun …` — `bun add -g` puts shims in `~/.bun/bin`, which is not on `PATH`,
    so the package installed and the command was still not found; they are now
    symlinked into `/usr/local/bin`. `setup bun` additionally links `node -> bun` when
    no real Node is present, since npm packages ship `#!/usr/bin/env node` shims that
    otherwise fail on a bun-only image (a genuine Node install is never shadowed).

- **Nineteen complex tests were never actually running.** `test-install-*`,
  `test-boothfile-apt`, and `test-boothfile-apt-snapshot` wrote their build-half
  check as `-- bash -lc '<cmd>'`. Everything after `--` is joined into one shell
  command line, so that flattened to `bash -lc <cmd>` — running `<cmd>`'s first
  word with `$0` set to the second, which fails quietly rather than loudly. The
  checks are now passed as a single quoted argument (`-- '<cmd>'`), which is also
  what `tests/basic` already did. The CLI is unchanged: the space-join is the
  documented `--` contract, and `tests/basic/test001--command.sh` depends on it to
  get a redirect inside the container. `install-pip` / `install-uv` additionally
  asserted the wrong CLI — PyPI's `cowsay` needs `-t`. **Once running, 13 of the 19
  pass and 6 fail on real defects in the install managers** (`deno`, `luarocks`,
  `pecl` fail the build outright; `cabal` leaves a dangling symlink into `/root`;
  `bun` puts binaries outside `PATH`; `conan` leaves an empty cache). Those are
  left failing deliberately — they are the breakage the skipped tests were hiding.

- **The `cb-local` test gate no longer goes stale.** `build/build-all.sh` now tags
  `cb-local/codingbooth:base-<version>` after a successful base build. That tag is
  what `use_local_base_image` gates on; it was applied by hand, so every version
  bump silently disabled the 23 tests that depend on it.

- **Skipped tests are reported instead of vanishing.** `tests/run-automate-tests.sh`
  counts skips per suite, shows them beside the pass tally, and prints a
  `Skipped: N` line in the summary. A self-gating test exits 0 and its remaining
  checks never print, so the totals used to just shrink — a run with 35 checks
  disabled still read `All tests passed`.

- **Documented how `--` is parsed.** [BOOTH_RUN.md](BOOTH_RUN.md#command-mode----cmd)
  now spells out that `booth -- …` is one shell command line (operators work,
  quoting does not survive) while `booth exec … -- …` is the opposite (argv passed
  straight to `docker exec`, no shell). The README's
  `booth -- python -c "print('hello')"` example was broken by this and is fixed.

- **Project-local templates, extensions, and recipes.** A booth can ship its own
  catalog under `.booth/templates/` (same category/`template.toml` /
  `*--extension.toml` layout as the stock tree). `booth config` (CLI + TUI) and
  `booth template list|show|…` load them automatically and **merge** them into the
  stock registry: same name → **local wins** with a stderr warning
  (`project template "go" overrides built-in …`). Bare recipe names resolve to
  `.booth/recipes/<name>.recipe` (`.recipe` appended when missing). Path-shaped
  `@` refs (`/…`, `./…`, `../…`, `~/…`, `C:\…`) and URLs (`@https://…` or `@@…`,
  with bare `@@host/path` assuming `https://`) still work. Missing recipe or
  unknown template/extension remains a hard error. Docs:
  [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md). Tests:
  `tests/config/test82-project-local-templates-and-recipes.sh` (config/dryrun) and
  `tests/complex/test-project-local/` (config + image build; markers
  `CB_DETECT_{TEMPLATE,EXTENSION,SETUP}_v1`).

- **Firebase host credentials win over empty/`{}` placeholders.** The
  `setup firebase` startup copies
  `/etc/cb-home-seed/.config/configstore/firebase-tools.json` into the home when
  the destination is missing, empty, or only `{}` (firebase-tools often creates
  that stub before login). A real login in the container is not overwritten.
  Documented mount path matches `firebase+credential` (single file). Fixes the
  firebase example when home-seed no-clobber would otherwise skip the host file.

- **Conservative team shared configs (no secrets).** Additional `shared-*`
  extensions for code-server keybindings/snippets, Neovim config, JupyterLab
  user-settings, XFCE keyboard shortcuts, and Starship prompt — all
  `shared-files`/`shared-dirs` only. Docs list explicit non-goals (IDE extension
  stores, JetBrains licenses, credentials, shell history).
- **DBeaver drivers and SQL scripts as separate shared extensions.**
  `dbeaver+drivers-shared` mounts `DBeaverData/drivers/` **and**
  `workspace6/.metadata/.config/` (for `drivers.xml` registry — jars alone still
  re-download). `dbeaver+scripts-shared` mounts project `Scripts/`. Sample
  gitignores for driver jars / metadata config.

- **`.booth/shared/` — team/git live state.** First-class bind mounts for selected
  paths outside `/home/coder/code` that are **meant to be committed** (mirror of
  `.booth/cache/` layout, opposite git policy). Config keys `shared-files` /
  `shared-dirs`; docs in [BOOTH_SHARED.md](BOOTH_SHARED.md). Opt-in extensions:
  `google-chrome+bookmarks-shared`, `chromium+bookmarks-shared`,
  `firefox+bookmarks-shared`, `codeserver+settings-shared`,
  `dbeaver+connections-shared`.
- **Chrome/Chromium `+profile-cache` paths fixed** to `~/.chrome-data` (matches the
  setup wrappers’ `--user-data-dir`), not `~/.config/google-chrome` /
  `~/.config/chromium`.
- **Chrome bookmarks shared as `Default/` directory, not a single Bookmarks file.**
  Chrome renames `Bookmarks.tmp` → `Bookmarks`, which detaches a file bind-mount;
  bookmarks never reached the host. Docs + extensions updated; shared walker skips
  non-container paths (e.g. `README.md` under `.booth/shared/`).
- **Fix Google Chrome setup key import in Docker builds.** Overwriting an existing
  apt keyring with `gpg --dearmor -o` without `--batch --yes` prompts on `/dev/tty`
  (missing in BuildKit), which aborted `setup google-chrome` with curl (23).

- **Fix GitHub “latest” version resolution under minified API JSON.** Several setup
  scripts used `grep '"tag_name"' | sed 's/.*"v?\([^"]+\)".*/\1/'`, which on a
  single-line (minified) release payload captures the *last* quoted token — often
  the reactions key `"eyes"` — instead of the tag. That broke `setup mkcert`
  (`Invalid mkcert version resolved: 'eyes'`) and `setup buf` during complex
  tests. Parsing now extracts the `tag_name` key with `grep -oE`, and mkcert/buf
  fall back to a known-good pin when resolution still fails.
- **Browser settings and extensions via shared (not cache).** Opt-in
  `+settings-shared` and `+extensions-shared` for Google Chrome, Chromium, and
  Firefox — all use `shared-dirs` under `.booth/shared/` only. Chrome family:
  settings → `Default/`, extensions → `Default/Extensions/`. Firefox: whole
  `~/.mozilla/firefox/` (profile holds prefs and add-ons).
- **Browser managed-policies extensions + sample gitignores.**
  `+managed-policies` runs `chrome-managed-policies` / `firefox-managed-policies`
  setups (enterprise JSON under `/etc/…`). Sample `.gitignore` files under
  `docs/samples/` for Chrome `Default/` and Firefox `firefox/`. Example workspace:
  `examples/workspaces/browser-shared-example/`.

- **Binary companion templates (Phase 1).** Selectable tools for companions that used
  to need raw `*-pkg` knowledge: `protobuf` (apt `protobuf-compiler` / `protoc`, with a
  `go` extension for `protoc-gen-go` and `protoc-gen-go-grpc`), `buf` (official GitHub
  release binary via `setup buf`), standalone `ffmpeg`, and standalone `graphviz`.
  Remotion/VHS/PlantUML still install their own companions. See
  `docs/TODO-BINARY_COMPANIONS.md`.

- **`dotnet-pkg` / `install dotnet` (Phase 2 binary companions).** Global .NET tools
  via `dotnet tool install --global`, selectable as `csharp+dotnet-pkg:dotnet-ef` (also
  under the `dotnet` template). Pins with `package@version`. Closes the Entity Framework
  CLI gap without a one-off template per tool. See `docs/TODO-BINARY_COMPANIONS.md`.

- **Browser companion stacks (Phase 3 binary companions).** Playwright-shaped setups for
  tools that need a second-step browser/driver download: `puppeteer` (shared
  `PUPPETEER_CACHE_DIR=/opt/puppeteer`), `cypress` (shared `CYPRESS_CACHE_FOLDER=/opt/cypress`),
  and `selenium` (Chrome for Testing + chromedriver under `/opt/selenium`; optional
  geckodriver). Avoids Ubuntu snap-stub packages for chromium/firefox. See
  `docs/TODO-BINARY_COMPANIONS.md`.

- **Binary companions docs catalog (Phase 4).** [BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y)
  lists “library X → also select Y” for dedicated templates and `*-pkg` recipes
  (protoc, buf, ffmpeg, browsers, ORM CLIs, …), with a pointer from
  [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md).

- **Harden cross-platform volume bind filtering.** Missing host bind-mount paths (`-v` / `--volume`) are skipped at runtime so Docker Desktop does not create empty directories for OS-specific credential locations. Windows drive-letter specs parse correctly, named volumes are preserved, CommonArgs (e.g. TLS cert mounts) are included, and skips are reported on stderr. See `docs/BOOTH_HOME.md`.
- **The config TUI now has a field for every setting a booth can hold.**
  It reached 18 of the 48 keys a `config.toml` may contain; the other 30 — `idle-time`,
  `persist-home`, `timezone`, `project-name`, the egress detail keys, `cmds`, the cache
  lists, and the rest — were reachable only by hand-editing or `--set`. All of them have
  fields now, grouped into Container, Egress, Build, Cache, Session and Temp Files
  sections. Integer settings get a digits-only editor and are written unquoted, which
  they have to be: `idle-time = "30"` fails the TOML decode and takes the whole booth
  with it.

  The field list is no longer hand-kept. It is generated from the settings booth actually
  reads, so a setting added to booth has no field until one is written for it (a test
  says so), and one removed from booth loses its field automatically. The hand-kept copy
  is what drifted before — and while it was adrift, a TUI save deleted the settings it
  had fallen behind on.

  Two things this surfaced. The **Version** field was labelled and documented as the
  prebuilt image tag but had always been wired to `--version`, the *template release* the
  configure run compiles from — it never wrote the `version` key at all. It is now
  **Templates Version**, with **Image Version** alongside it for the real setting. And
  reconfiguring a booth **grew its cache lists**: a `cache-files` entry was applied both
  from the existing `config.toml` and from the `Configured by:` header, so it doubled on
  every save. Both fixed. See
  [booth config — the Config tab](BOOTH_CONFIG_TUI.md#the-config-tab).

- **A booth on a git worktree (or submodule) now starts.**
  The base image installs a `git lg` convenience alias at container start. Git runs repo discovery
  before *every* subcommand — including `git config --global`, which needs no repo — so in a
  workspace whose `.git` is a dangling gitfile (a worktree or submodule, whose real git dir lives
  outside the mount) that alias exited `128`. Under `set -euo pipefail` it took the entrypoint with
  it, and the booth died before running anything: not the user's command, not `.booth/startup.sh`,
  not a build. `booth exec --run -- echo hello` failed with `did not become ready in time` and a
  container `Exited (128)`. The alias is now guarded — skipped when git is absent, run from `/`
  (the only directory with no possible `.git` ancestor) otherwise, and never fatal.

- **Removed the unused `variants/base/setups/libs/git-on-token.sh`.**
  It configured git identity and a `gh` credential helper from `GH_TOKEN`, but had no callers
  anywhere in the repo. It also carried the same startup-fatal hazards described above — unguarded
  `git config --global` calls plus `exit 1` on a missing or invalid token — so wiring it in as-is
  would have prevented the booth from starting for any user without GitHub credentials. Removed
  rather than repaired, since nothing used it.

  Note this makes the booth *start* on a worktree; it does not make git *work* inside one. The
  parent repo's `.git/worktrees/<name>` is still outside the mount, so in-booth `git status`,
  `lazygit`, and `gh` will not find the repo. Full worktree support is a separate change.

- **`booth exec` accepts `--daemon` (`-d`) to start a command detached.**
  The command is started inside the booth and `exec` returns immediately, so long-running things
  (a dev server, a watcher, a build daemon) can be launched without holding the terminal:
  `booth exec myproject --daemon -- bash -c './server >/tmp/server.log 2>&1'`. Detaching trades away
  the result — no output is streamed back and the command's exit code is not forwarded, so `exec`
  exits `0` once the command has *started*; redirect output inside the container to keep it. Two
  combinations are refused rather than silently misbehaving: `--daemon -it` (a detached command has
  no terminal to attach to) and `--daemon --run` without `--keep-alive` (the booth would be stopped
  the moment `exec` returns, killing the command that was detached to outlive it). The same check
  applies to a booth an earlier `--run` left ephemeral. `booth shell` is unaffected — detaching an
  interactive shell has no meaning.

- **The default container name auto-suffixes with the port on collision instead of failing.**
  Running the same project twice used to error (`container name "myproj" already exists`). Now the
  first booth keeps the stable folder-derived name (`myproj`) and a second concurrent booth of the
  same project auto-falls back to `myproj-<port>` — no extra flags, and the port is already unique
  because `--port` defaults to `NEXT`. The stable base name stays with the first booth, so no-argument
  lifecycle commands (`booth stop` / `remove` / `restart`) still target it. This applies only to the
  derived default name; an **explicit** `--name` remains a contract that errors on collision (use a
  `{project}-{port}` placeholder when you want an explicit-but-unique name).

- **`--port NEXT` / `RANDOM` can start from a chosen base: `NEXT:<base>` / `RANDOM:<base>`.**
  Both symbolic port modes previously always scanned from 10000; now an optional `:base` suffix
  moves the starting point, e.g. `--port NEXT:20000` picks the first free port ≥ 20000 and
  `--port RANDOM:20000` a random free one ≥ 20000 (still stepping by 1000). `NEXT` is unchanged and
  equals `NEXT:10000`. This lets related projects claim separate, predictable port bands while still
  auto-avoiding collisions. `<base>` is validated 1–65535; a malformed base is a clear error. The
  `:base` forms remain create-only symbolic values, so `exec`/`shell --run --port NEXT:20000` is not
  asserted against an existing booth's port.

- **`--name` accepts `{port}` / `{project}` / `{variant}` placeholders, resolved after port
  selection.** Running several booths of the same project used to collide on the container name
  (it defaults to the folder name) even when `--port NEXT` avoided the port collision — you had to
  hand-pick a port and thread it into `--name` yourself (`PORT=12000 booth --port $PORT --name gp$PORT`).
  Now the name can follow the auto-picked port: `booth --port NEXT --name '{project}-{port}'` picks a
  free port and names the container `myproj-12000` in one command, so a second run lands on
  `myproj-13000` with no collision on either axis. The template is stored literally (so
  `name = "{project}-{port}"` in `config.toml` re-resolves every run) and expanded in the run pipeline
  right after `PortDetermination`; literal characters that are not Docker-name-safe are replaced with
  `-`. It mirrors how booth-relative `+OFFSET` publishes let service ports follow the booth port. Works
  through `booth exec`/`shell --run` too: because the resolved name is only known after the run, the
  created container is located by diffing the booth set before and after.

- **List a booth's ports, from either side.** `booth expose list` (host) reports every
  port a booth publishes — the front door, published `-p` ports, and runtime tunnels — and
  confirms each against `docker port`. Inside a booth, `booth--expose list` shows the same
  ports plus which process is listening on each (from `ss`), including internal-only services
  that are not published. Both read a new run-time manifest, `.booth/.tmp/ports.json`, written
  by the run pipeline after the ports are resolved; when it is absent (an older booth) the host
  command falls back to the live `docker port` view. See `docs/BOOTH_EXPOSE.md`.

- **A host-env expose port can fall back to a booth-relative offset: `${SERVER_PORT:-+300}:1234`.**
  The two host-side forms now compose. Previously a `${NAME:-default}` fallback had to be a fixed
  number, so a published port was either env-overridable (`${SERVER_PORT:-12345}`) or booth-relative
  (`+300`), never both. Now `${SERVER_PORT:-+300}:1234` publishes on `$SERVER_PORT` when the variable
  is set and on `boothPort + 300` when it is not — a default that follows the booth port so two booths
  of the same project stop colliding, without baking a fixed host port into the config. It works
  because `${…}` is expanded at TOML unmarshal, *before* `ResolveRelativePorts` runs: expansion yields
  `+300:1234`, then the offset step rewrites it against the booth port. Only the config-time validation
  had to change — it rejected the `+` in the fallback.

  A `+OFFSET` fallback requires an explicit `:CONTAINER`: the bare `HOST:HOST` shorthand would put the
  `+OFFSET` on the container side too, which is not a port, so `--expose '${SERVER_PORT:-+300}'` is
  refused with a message pointing at the missing container port.

- **Web apps get a desktop icon that opens them in a browser.** Server-style tools that serve an
  HTTP UI on an internal port — Jupyter Notebook, CloudBeaver, Scratch — now get a desktop launcher
  (and, on the Wayland variant, a panel button) that opens the service in a dedicated app-mode
  browser window. Because the desktop session runs inside the same container, the launcher points
  straight at `http://localhost:<internal-port>` — no host mapping or proxy. A setup registers one
  with `cb-web-icon`, which drops the launcher into the same `/etc/skel/Desktop` registry the app
  icons use; at click time `cb-web-open` resolves the port from its env var (falling back to the
  default), appends an access token when one is set, starts the service if it is not already
  listening, and opens it.

  Two launch fixes rode along. On **XFCE**, desktop launchers no longer trip Thunar's "insecure
  location / Mark Executable" prompt: they are stamped with the `metadata::xfce-exe-checksum` that
  `libxfce4util`'s trust check expects (the same value "Mark Executable" writes) before the desktop
  loads. And on **Wayland**, the waybar buttons launch each app's `Exec` directly instead of via
  `gtk-launch`, which the Wayland image does not ship — so every panel button works, not just the
  new ones.

- **`mkcert` install survives GitHub rate limits.** A full `--no-cache` build+test run can exhaust
  the unauthenticated GitHub API/download budget, and `curl --retry` alone does not retry an HTTP
  429 or 5xx — so the mkcert binary download failed hard and took the booth build (and
  `test-boothfile-mkcert`) down with it. The GitHub API call and the binary download now pass
  `--retry-all-errors`, and a download that still fails falls back to the pinned known-good version
  before giving up.

- **`shell` / `exec` accept create-time `--port` and fail on mismatch by default.** With `--run`, a missing booth is created via `booth run --daemon`, and `--port` (number, `NEXT`, or `RANDOM`) is forwarded so the new booth gets the host UI port you asked for — same for `--name` / `--keep-alive` as before. Against an **existing** booth, an explicit numeric `--port` is a contract: if it does not match the published host port, the command **refuses to connect** (so scripts do not run against the wrong environment). Pass **`--accept-existing`** to connect anyway with a warning on stderr. Symbolic `--port NEXT` / `RANDOM` are only applied on create and are not compared. Unit tests cover the mismatch rules and run-arg construction; complex test `tests/complex/test-connect-run-port/` exercises create, match, refuse, accept-existing, `NEXT`, and ephemeral teardown. See `docs/BOOTH_CONNECT.md`.
- **Desktop apps now appear as icons on the graphical desktop.** On the XFCE, KDE, and LXQt
  variants, every selected GUI application — VS Code, the JetBrains IDEs, DBeaver, Firefox, Chrome,
  Chromium, GIMP, Inkscape, LibreOffice, Obsidian, Eclipse, Antigravity, Thonny, BlueJ, Greenfoot —
  drops a launcher on the desktop that runs on double-click. On XFCE the icons are laid out
  top-centre, spreading left and right as more are added; the Wayland (labwc) variant draws no icon
  surface, so each app becomes a button on the waybar panel instead. A setup registers its launcher
  by calling `cb-desktop-icon <app>`, which copies the matching `.desktop` into `/etc/skel/Desktop`;
  `booth-entry` seeds that directory into each user's `~/Desktop`, and both the XFCE arrangement and
  the Wayland panel derive their app list from it, so one registry drives every variant.

- **Three fixes made those launchers actually work.** `cb-has-desktop.sh` now recognises labwc (and
  the other wlroots compositors), so desktop-only setups such as PyCharm and DBeaver install on the
  Wayland variant instead of silently skipping. The VS Code launcher wrapper no longer hard-codes
  `DISPLAY=:1`; it honours the session's display — `:0` (Xwayland) on Wayland, `:1` (VNC) elsewhere —
  so clicking VS Code opens it rather than failing to find a display. And on LXQt, `~/Desktop`
  launchers are marked trusted (`gio set … metadata::trusted`) before the pcmanfm-qt desktop renders,
  so they no longer carry an "untrusted" emblem or ask for confirmation on first launch.

- **`booth build` now expands variant aliases, so it works for the configs `booth config` writes.**
  The variant names the base image tag, and only the canonical names (`base`, `codeserver`,
  `desktop-xfce`, …) are published — the aliases (`xfce`, `ide`, `desktop`, `console`, …) are expanded
  by `ValidateVariant` before the tag is assembled. The run path did that; `booth build` never called
  it, and passed the alias through raw. A project whose `config.toml` says `variant = "xfce"` — which
  is exactly what `booth config --variant xfce` writes — therefore failed with
  `nawaman/codingbooth:xfce-<version>: not found` on the `FROM` line, while `booth run` on the same
  project built fine. An unknown variant is now refused by `booth build` too, rather than handed to
  docker as a bogus tag.

- **A booth no longer generates a config docker refuses to start.** Docker cannot bind one host
  port twice — it fails the container with `address already in use` — and run-args grew duplicates
  in two ordinary ways. A template's short-form `-p` plus the user's long-form `--publish` for the
  same mapping (`cloudbeaver+expose --expose 8978:8978`) were both emitted, because the two flag
  forms are deliberately not deduped against each other. And two templates could resolve to the
  same mapping (`nginx+expose/apache+expose`, both `8080:80`) because the compiler's dedup runs
  *before* params are expanded, so it compares `${NGINX_PORT}:80` against `${APACHE_PORT}:80` and
  finds them different. Neither combination needed a hand-edited config to reach; both simply did
  not start.

  Identical mappings are now collapsed (the user-owned `--publish` is the one kept, since it is
  what `booth config` reads back into `--expose` when re-configuring). Anything that genuinely
  cannot bind is refused at start with both mappings named, instead of docker's `driver failed
  programming external connectivity`. That check runs after `+OFFSET` resolution, so it also
  catches an offset that lands on an absolute mapping, and it accounts for the booth's own port —
  `--expose 20000:8978` on a booth at 20000 is now an error rather than a mystery. Publishing one
  *container* port on two host ports stays legal, because docker allows it; but a `--expose` that
  does so now says that it adds a second mapping rather than moving the first, and points at
  `+expose:<port>`, which does move it.

- **An expose host port can be booth-relative: `rabbitmq+start+expose:+4567`.** A `+OFFSET` host
  port stays literal in `run-args` (`"-p", "+4567:5672"`) and resolves at container start as
  `boothPort + OFFSET`, so a booth on port 20000 publishes AMQP on 24567 — and two booths of the
  same project on different ports stop colliding on published ports. A bare number is still an
  absolute host port; the `+` is what makes it relative.

  The resolution itself is not new — `--expose +4567:5672` and hand-written `run-args` have always
  been rewritten this way, for template-contributed `-p` as much as user-set `--publish`. What was
  missing was any way to *say* it in a selection: the DSL splits an item on `+` to find its
  extensions, so `expose:+4567` parsed as an extension named `4567` ("unknown extension"). Inside a
  param list a `+` now starts an extension only when followed by a letter — names are identifiers
  and never digit-initial — so `expose:+4567+start` is a relative port *and* a `+start` extension,
  while a malformed `go++linter` still reports an empty extension name. It also makes
  `apt-pkg:libstdc++6` parse, which errored out before.

- **The booth now refuses to start unless `.booth/cache/` is gitignored *and* untracked.** The
  cache is whatever the container writes to the mounted paths, and with `claude-code+settings-cache`
  that includes a live credential: `~/.claude/` is mounted as a whole directory, so the host token
  the `/etc/cb-home` override layer copies to `~/.claude/.credentials.json` on every start is
  written straight back into your project tree, next to `history.jsonl` and the `projects/`
  transcripts.

  The old check greped `.booth/.gitignore` for a `cache/` line, which cannot see the failure that
  actually happens: **gitignore does not apply to files git already tracks.** Once a cache file is
  in the index — force-added, or added before the rule existed — git keeps committing it and the
  grep still reports green. The check now asks git, and fails two ways: `is NOT gitignored` (add the
  rule) and `is tracked by git` (`git rm -r --cached .booth/cache`, then **rotate any credential
  that was committed** — a gitignore rule will not untrack it for you). Projects that are not git
  repos are unaffected: there is nothing to commit to, so the check is skipped, matching
  `.booth/.env`.

  `.booth/.gitignore` had two writers — `booth config` and the wrapper script, which has to write it
  before the CLI binary exists — and they had drifted into twelve variants in the wild. Both now
  emit one canonical block (`output.BoothGitignore`), pinned by a test that diffs the wrapper's
  heredoc against the constant. This was not cosmetic: both writers overwrite the file
  unconditionally, so a rule only one of them knew about vanished as soon as the other ran. The
  wrapper emitted the `tools/` rules only for `--cache=local`, so the first `booth config` in such a
  project un-ignored the downloaded binaries; those rules are now always present (a no-op in
  shared-cache mode, where `tools/` holds nothing but the lock file).

  A cache entry that maps onto a protected container path (`/home/coder/code`, `/opt/codingbooth`)
  is now an error naming every offender, not a warning that silently drops the mount — as the docs
  had always claimed. A skipped mount is indistinguishable from a cache that inexplicably does not
  work.

- **`expose` extensions now have a host port you can move on its own.** The host side and the
  container side of the published mapping were the same param, so the only way to get off a busy
  host port was to move the service inside the booth as well. Each `expose` extension now declares
  its own `*_HOST_PORT` (`SSH_HOST_PORT`, `CLOUDBEAVER_HOST_PORT`, …) defaulting to `"${SVC_PORT}"`
  — a reference, so `cloudbeaver:25.3.5,9000+expose` still publishes `9000:9000` and the two cannot
  drift apart, while `cloudbeaver:25.3.5,9000+expose:19000` publishes `19000:9000`. `rabbitmq` takes
  both of its ports positionally: `rabbitmq+start+expose:15672,25672`. Defaults are unchanged, so
  existing configs regenerate byte-identically. In the TUI a followed port renders as its resolved
  value with a `(follows SVC_PORT)` note rather than the raw `${SVC_PORT}`; editing the field shows
  the reference, so overwriting it is a deliberate pin rather than an accident.

  Param pins carried over from an existing Boothfile now distinguish a value the user *chose* from
  one the last generation *derived*. `arg` lines hold resolved values, so a followed host port
  reaches the Boothfile as a number and string comparison alone cannot tell `SSH_HOST_PORT=2200`
  ("I want 2200") from `SSH_HOST_PORT=2200` ("that is what `${SSH_PORT}` came to"). Re-resolving the
  default against the Boothfile's own args reconstructs the derived value: a match re-derives from
  the new selection, anything else is preserved as before. Without it, re-configuring
  `openssh+server:2200+expose` to `openssh+server:22+expose` published 2200 while sshd listened on
  22 — the very drift the host-port param exists to prevent.

- **A param default can now reference another param.** Writing `default = "${SVC_PORT}"` used to be
  a coin flip: param expansion was a single pass over a Go map, so `-p ${SVC_HOST_PORT}:${SVC_PORT}`
  came out as `8080:8080` or as a dangling `${SVC_PORT}:8080` depending on the run's map iteration
  order. Param values are now resolved to a fixpoint before anything consumes them, so run-args,
  `arg` lines and startup scripts all see literals. Circular defaults are a compile error naming the
  cycle; a reference to a name that is not a param (`${HOME}`) is still passed through untouched for
  the shell to expand at runtime. This is what lets an `expose` extension carry a host port that
  *follows* the port the service actually listens on rather than a hardcoded literal.

- **Server templates can now auto-start and publish themselves.** `notebook`, `codeserver` and
  `ollama` each installed a server and then left it sitting there: `start-notebook` and
  `start-codeserver` were on `PATH` but nothing called them, and Ollama's startup hook only created
  `~/.ollama` while its docs told you to run `ollama serve` by hand. Each now gets the
  `autostart` + `expose` extension pair that `excalidraw`, `mermaid`, `plantuml` and `cloudbeaver`
  already had — so `--select notebook+autostart+expose` puts JupyterLab on 18888 next to your
  code-server or desktop, reachable from the host.

  `notebook` and `codeserver` are both a template *and* a variant, and on their own variant the
  server is already the primary service **on that same port** (JupyterLab on 18888, code-server on
  19999, each behind the booth's nginx). Auto-starting there would not be merely redundant, it would
  collide — so both startup scripts bail out on the matching variant. The port is now a param
  (`NOTEBOOK_PORT`, `CODESERVER_PORT`, `OLLAMA_PORT`) instead of a hardcoded literal.

  `nginx` and `apache` get `expose` only. They already auto-start from their own
  `/usr/share/startup.d/` hook, but nothing published the port, so the daemon was unreachable from
  the host. Both serve on container port 80, and the extension maps a host port to it
  (default 8080) — which also means they cannot share a booth.

- **Java notebook kernels installed nothing on the `base` variant.** All three Java kernel setups
  (`java-nb-kernel`, `java-ijava-nb-kernel`, `java-jjava-nb-kernel`) opened with a guard that exited 0
  when `BOOTH_VARIANT_TAG == base`, printing "Variant does not include VS Code (code) or CodeServer" —
  a message about VS Code, in a Jupyter kernel installer. It was copy-pasted from a VS Code extension
  setup. None of the other fourteen notebook kernels (bash, python, go, rust, scala, kotlin, …) carry
  it. The effect was that `java+kernel/notebook` on `base` built successfully and silently produced no
  Java kernel. The guard is removed; the setups already check what they actually need (python with
  `jupyter_client`/`jupyter_core`, `javac`, `JAVA_HOME`).

- **`coder` now owns uid 1000 in the base image.** Ubuntu 24.04 (noble) ships a stock `ubuntu` user
  holding uid/gid 1000, so `free_uid()` handed `coder` 1001 — and 1000 is the uid nearly every Linux
  host has. `booth-entry` therefore renumbered `coder` and re-owned `$HOME` on *every* start. With
  large host directories bind-mounted under `/home/coder` (a `~/.m2`, a project tree, a `.booth/cache`)
  that reconcile was slow enough to look like a hang — booths took minutes to start. The stock `ubuntu`
  user is deleted at build time, so the uids already agree and the renumber is skipped entirely.

- **Setups retry their network fetches instead of failing the build on a blip.** Two of them pulled
  from the network with no retry at all, and a single connection reset took the whole image down.

  `go--install.sh` ran `go install` bare. It fetches through proxy.golang.org, which resets connections
  often enough that this was the single most common cause of a failed build — it took out an entire
  test suite three times in one day. Go has no retry of its own, so the call is now wrapped in one
  (3 attempts, backing off). A genuinely broken package still fails, just three attempts later.

  `kafka--setup.sh` fetched from `downloads.apache.org`, a CDN that only carries the *current* release
  — so it 404s for any pinned older version and every build falls through to `archive.apache.org`,
  which is durable but throttled. The archive fetch now retries (`--retry-all-errors`, because curl
  does not treat a reset mid-transfer as retryable on its own); the CDN still fails fast, since a 404
  is not worth retrying.

- **Credential extensions now seed credentials, not whole application-state directories.**
  `aws-cli`, `aws-sam-cli`, `azure-cli`, `gcloud`, `kubectl` and `codex` each mounted the tool's entire
  home directory into `/etc/cb-home-seed`, and every one of them is `auto-select = true`. Because that
  seed is copied into the container home on every start, the copy swept up whatever else lived there:
  gcloud writes a log file per invocation (733 of 741 files in a normal `~/.config/gcloud`), `az` writes
  a telemetry file per invocation and unpacks extensions as full Python packages, kubectl caches a
  discovery document per cluster, and `~/.codex` keeps a transcript of every conversation. None of it is
  a credential, and all of it was copied into every container.

  Each now mounts the specific credential and settings files. Mounts whose host path does not exist are
  already dropped before `docker run` (`FilterMissingVolumeMounts`), so listing paths that only some
  users have — `application_default_credentials.json`, an SSO session cache, the Windows gcloud layout —
  costs nothing. What is intentionally left behind is spelled out in each extension's `display-detail`.

  `antigravity` and `cursor` are **not** narrowed: they are VS Code forks that need most of their
  `User/` directory to stay signed in, so they need cache *exclusion* rather than file selection, which
  `smart_copy` has no mechanism for yet.

- **Home-seeding no longer forks a subprocess per file.** `booth-entry`'s `smart_copy` walked
  `/etc/cb-home-seed` and `/etc/cb-home` entry by entry, forking `basename` *and* `cp` for every one,
  because any directory below might carry a `.mount-this` marker asking to be copied as a unit. No
  marker ships in any template and host directories never have one, so in practice the walk always ran
  to the bottom — at roughly 56 files/sec. A booth seeding a real home directory took *minutes* to
  start, and looked hung.

  A subtree with no marker anywhere below it has nothing that can change the copy's behaviour part-way
  down, so it is now taken in a single recursive `cp` (`-L`, matching the walk, which tested entries
  with `[ -f ]` / `[ -d ]` and so copied link targets rather than links). The walk is kept for subtrees
  that do carry a marker. Copying 20,000 files went from **146s to 0.65s**, with identical output.

- **`booth config --no-tui` now reads the existing booth as its baseline, like the TUI does.** It only
  ever read `config.toml`'s long-form run-args, never the `# Configured by:` header — so a reconfigure
  that did not restate `--select` rebuilt from an *empty* selection. The Boothfile escaped by luck (an
  empty one serializes to nothing, and the writer skips empty content), but `config.toml` was rewritten
  regardless: `variant`, `port`, `cmds` and every template-contributed run-arg were dropped, while the
  envs and mounts survived because those are recovered from `config.toml` itself. Losing the `variant`
  silently rebuilds the booth on the wrong base image. The header is now parsed back as the baseline,
  so a reconfigure need only state what changes.

  The flags that steer the run — `--overwrite`, `--beside`, `--dryrun`, `--start` — are deliberately
  *not* inherited: the header records the `--overwrite` that wrote it, so inheriting them would make
  every later run an overwriting one and quietly disarm the hand-written-file guard.

  Restating a list flag (`--env`, `--mount`, `--expose`) now **replaces** the saved list rather than
  unioning with it — which is what makes removing an entry possible. Omitting the flag still keeps it.

- **New Java template extensions.** `java/kernel-jjava` installs the JJava notebook kernel
  (dflib/jjava, Java 11+) as an alternative to `java/kernel`, which installs IJava — pinned at 1.3.0
  and predating the modern JDKs the template offers. Pick one, not both: they install over the same
  `java` kernelspec. `java/jbang` pre-warms the jbang dependency cache at build time, so the first
  jbang run (or Java notebook cell) does not stall on the network.

- **`examples/demo` is now generated by `booth config`** rather than hand-written, so it can be
  reopened and edited in the config TUI.

  Its `~/.claude` home-seed mount is narrowed to `~/.claude/settings.json` in the process. The mount
  was labelled "credentials" but seeded the whole directory — 418 MB of conversation transcripts, jobs
  and file-history — into the container on every start, and because the `claude-code` template
  bind-mounts `/home/coder/.claude` to the project's `.booth/cache/`, that copy landed in the project
  tree. Credentials were never the reason it worked: the template already seeds `~/.claude.json` and
  overrides `~/.claude/.credentials.json`. Seeding an entire application-state directory is the
  anti-pattern here — mount the credential files, not the app's home.

- **`booth config` no longer silently destroys a hand-written Boothfile / config.toml.** Configuring
  regenerates both files from scratch, so a hand-written booth — or a generated one that was later
  hand-edited — lost that content on the next `booth config`, with no warning. The `# Configured by:`
  header could not prevent this: it survives a hand-edit, so it cannot distinguish "still ours" from
  "someone edited this". `booth config` now fingerprints (SHA-256) what it writes, recording it in
  `.booth/.generated`, and compares before overwriting. Content it did not write is now protected, and
  "overwrite or give up" is not the only way out — you get two choices, in the TUI on save or as flags:

  - **Keep yours** (`--beside`, or `Enter` in the TUI): the generated content is written alongside as
    `<name>.new` and your file is not touched, for you to merge by hand — the same idea as
    `pacnew`/`rpmnew`/`dpkg-dist`. Nothing is destroyed, and the kept file stays guarded until you
    actually merge it. This is the TUI's default.
  - **Replace yours** (`--overwrite`, or type `overwrite` in the TUI): your file is replaced and kept
    as `<name>.bak`. Destroying work takes more than a reflex keystroke; getting at the generated
    output does not.

  The config TUI also says so **up front**, in a yellow dialog on open (Enter to continue) — otherwise
  you would configure an entire booth before discovering, at save time, that the result could not
  simply be written over what you have. It is a heads-up, not a blocker: nothing is touched until you
  save, so you are still free to go in and look around.

  `.bak` and `.new` are gitignored. A booth generated before `.generated` existed is adopted on its
  header, so no existing project starts crying wolf. Hand-written booths are the norm — every
  `examples/workspaces/*` booth is one — so this covers the mainstream case, not an edge case. See
  `cli/src/pkg/boothinit/output/guard.go` and `writer.go`; tests
  `tests/config/test68-config-guards-handwritten.sh` and
  `tests/config-tui/test15-tui-overwrite-guard.sh`.
- **New `desktop-wayland` variant (experimental) — a Wayland-native desktop in the browser.** The existing
  `desktop-xfce`/`desktop-kde`/`desktop-lxqt` variants are X11 (TigerVNC + noVNC);
  `desktop-wayland` runs [labwc](https://labwc.github.io/) (a wlroots compositor) on the
  headless wlroots backend and streams it via [wayvnc](https://github.com/any1/wayvnc)
  (`wlr-screencopy` → RFB) through the **same** websockify + noVNC delivery over the single
  booth port — only the compositor and VNC server change (TigerVNC/X11 → labwc+wayvnc/Wayland).
  The wlroots headless backend needs no logind/seat, `wlr-screencopy` reliably captures the
  session, and existing X11 apps (Firefox/Chrome/VS Code) run via Xwayland. Selected with
  `--variant wayland` (alias of `desktop-wayland`). No VNC password by default (localhost
  model, like the other desktop variants); `--public` password auth via wayvnc TLS is a
  follow-up. New setup `variants/base/setups/wayland--setup.sh`; wrapper `start-wayland-wrapped`;
  template `templates/desktops/wayland/template.toml`. See `docs/BOOTH_VARIANTS.md` and
  `variants/desktop-wayland/README.md`.
- **Fix flaky `setup jdk` builds — JBang no longer pulls its own bootstrap JDK.** `jdk--setup.sh`
  installed JBang before the JDK, so on a fresh image JBang found no `javac`/`JAVA_HOME` and
  downloaded a bootstrap JDK from `api.foojay.io` — the exact flaky download the script's
  direct-download strategy (Temurin/Corretto) exists to avoid. Under `set -o pipefail` a foojay
  outage aborted the whole build at the `curl … sh.jbang.dev | bash` step. For direct-download
  vendors the JDK is now installed first and `JAVA_HOME` exported before JBang runs, so JBang
  reuses it and skips the bootstrap download entirely; JBang-fallback vendors (openjdk, graalvm)
  are unchanged. The `sh.jbang.dev` fetch also gains `--retry 3`. Fixes `tests/config/test01-init-cli-basic`
  and `tests/complex/test-boothfile-gradle`. See `variants/base/setups/jdk--setup.sh`.

## 0.64.0

- **`booth shell-config` restores the shell convenience layer (bash, zsh, fish).**
  `shell-config install` copies the wrapper to an OS data directory
  (`~/.local/share/codingbooth/booth` on Linux, Application Support on macOS,
  LocalAppData on Windows) and installs an idempotent, marker-fenced `booth()`
  function into `~/.bashrc`, `~/.zshrc`, and fish `conf.d/codingbooth.fish`.
  The function walks up from `$PWD` for a project `./booth` and falls back to
  the central wrapper; project commands without a project still fail with the
  usual messages. Markers:

  ```
  # >>> codingbooth shell-config begin >>>
  ...
  # <<< codingbooth shell-config end <<<
  ```

  `shell-config uninstall` removes the block and the central copy;
  `shell-config status` reports install state. The one-liner installer now runs
  `shell-config install` after `booth install`.

- **Central `booth install` copies `./booth` into `$PWD` before installing.**
  Invoking install via the central wrapper (shell-config fallback) used to write
  `.booth/` next to the central script. It now places a project wrapper in the
  current directory, re-execs that wrapper, and installs the lock/binary there.
  The shell `booth()` function also appends `--code <project-root>` when walk-up
  finds a project booth above `$PWD` (so subdir runs name/mount the project, not
  the subdir). **0.14.2:** install/update always target `$PWD` even when a parent
  `./booth` exists (walk-up no longer steals install into the parent).
  **0.14.3:** fish installs to `~/.config/fish/functions/booth.fish` (autoload);
  when `--code <dir>` is given, the shell function prefers `<dir>/booth` so the
  lock next to that project wrapper is used (not a parent `./booth`).
  **0.14.4:** fish no longer uses `cd` inside command substitutions (fish does
  not run those in a subshell), so `booth` from a project subdirectory no longer
  leaves the shell sitting in the project root.
  **0.14.5:** `./booth shell-config` defaults to install; new `./booth create <dir>`
  creates the directory and runs install inside it.

## 0.61.0

- **Every desktop variant now keeps the CodingBooth wallpaper instead of the stock desktop backdrop.**
  On XFCE, `xfdesktop` overwrote the seeded system default with its built-in `xfce-blue` backdrop on
  first login, so the brand wallpaper never appeared; the other desktops relied on a system default a
  first-run session could shadow just as easily. Each variant now re-applies the wallpaper once its
  session is up, so it wins regardless of first-run behavior — XFCE via `xfconf-query`, KDE via
  `plasma-apply-wallpaperimage` (falling back to plasmashell scripting over `qdbus`), and LXQt via
  `pcmanfm-qt --set-wallpaper`, each from an autostart entry; Wayland/labwc already writes `swaybg`
  into its session autostart on every start. The wallpaper image itself was refreshed. See the
  `*-wallpaper--setup.sh` scripts under `variants/`.

- **The base image build no longer stalls on IPv6-only mirror lookups.** `ports.ubuntu.com` (the
  arm64/ports mirror) publishes AAAA records, and on a build host without a working IPv6 route — the
  common case for the emulated arm64 leg under QEMU — `apt` preferred IPv6, stalled, and reported
  every package as "unable to locate", aborting the base build. The base image now writes an
  `Acquire::ForceIPv4` apt drop-in before its first `apt-get`, inherited by every downstream setup and
  variant, so package fetches use IPv4. See `variants/base/Dockerfile`.

## 0.59.0

- **`booth config` preserves pinned param values across reconfiguration.** Previously, reconfiguring a booth (e.g. adding or removing a template/extension) rebuilt the Boothfile entirely from the selection DSL and reset every non-default param — `NODE_VERSION`, `GO_VERSION`, `PYTHON_VERSION`, `PLAYWRIGHT_VERSION`, … — back to its template default, because pins live in the Boothfile's `arg NAME=VALUE` lines and were not carried by the stored selection. Now the resolver reads those `arg` lines back and preserves any non-default pin unless the new selection explicitly overrides it (explicit selection still wins).
  - This bit the Playwright example concretely: adding an unrelated extension silently reset the pinned Playwright version to `latest`, so the pre-baked browser no longer matched the version `npm ci` installed at runtime and headless launches failed with "Executable doesn't exist".
  - The config **TUI** now also loads real pinned values from the existing Boothfile into its param fields (instead of showing the template default), so what you see matches what is saved. New `selection.ResolveWithOverrides`; `readExistingArgs`/`overlayExistingArgs` helpers. Tests: `TestResolveWithOverrides_*`, `TestReadExistingArgs_*`, `TestOverlayExistingArgs_*`, `tests/config/test67-config-preserves-pin.sh`, and `tests/config-tui/test14-tui-preserve-pin.sh`. See `docs/BOOTH_CONFIG.md`.
- **Playwright template gains a `PLAYWRIGHT_VERSION` param.** `setup playwright` already accepted `--version`, but it wasn't reachable through `booth config`, so the version could only be hand-pinned in the Boothfile (and was lost on regeneration). Pin it with `--select playwright:chromium,1.58.2` (browsers stay the first positional; version is second). Default is `latest`; pin it so the pre-baked browsers match the Playwright installed at runtime. Multi-browser selection via the comma-positional CLI form remains a TUI path. Test: `tests/config/test66-init-playwright-version.sh`.
- **`npm-upgrade` config extension for Node.js.** Opt-in extension that upgrades the global npm to a newer version than Node.js bundles, via `run npm install -g npm@NPM_VERSION` at build time (`--select nodejs+npm-upgrade`, or `nodejs+npm-upgrade:11.18.0` to pin). Off by default — the npm that ships with the selected Node.js stays the reproducible baseline. Test: `tests/config/test65-init-npm-upgrade.sh`.

## 0.58.0

- **`shell` and `exec` can bring up a non-running booth with `--run`.** By default `booth shell` and `booth exec` require the target booth to already be running. Passing `--run` makes the booth available first and then connects — so you can jump straight into a booth from its workspace without a separate launch step.
  - It does whatever is needed: an already-running booth is used as-is; a stopped container (e.g. a `--keep-alive` booth) is started; and when **no container exists** — the common case, since stopping a normal booth removes it — a new one is created from the workspace with `booth run` in daemon mode.
  - A booth that `--run` brought up does not outlive the session: when you disconnect it is returned to its prior state (a created booth is removed, a stopped `--keep-alive` booth goes back to stopped, an already-running booth is left untouched). Pass `--keep-alive` to leave it running instead — which also creates it as a keep-alive booth so it survives a later `booth stop`. Interrupting with Ctrl+C still tears it down.
  - Concurrent `--run` sessions on the same booth are reference-counted (tracked under `/run/booth-run/` inside the container): the booth is only brought down when the **last** session disconnects, so one session exiting never kills another's still-attached booth. `--keep-alive` from any session promotes the booth to persistent.
  - Opt-in by design: without `--run`, a non-running booth stays an error, which keeps `booth exec` predictable in scripts and CI. The booth's startup output goes to stderr so `exec`'s forwarded stdout stays clean, and `shell`/`exec` wait for the container's `coder` user alignment to finish before connecting so the first command never races startup. New unit tests cover the resolve/start/run decisions, and `tests/manual/run-shell-run-manual-test.sh` exercises the real Docker path (run-from-scratch, keep-alive, start-stopped, and concurrent sessions). See `docs/BOOTH_CONNECT.md`.

## 0.57.0

- **Egress filtering — restrict a booth's outbound network to an allowlist of domains.** `--egress` (or `egress = true` in `.booth/config.toml`) routes the container's HTTP/HTTPS traffic through an Envoy forward-proxy sidecar with a domain allowlist, backed by iptables rules that drop any direct egress — a defense-in-depth layer for running third-party AI agents or untrusted dependencies that bounds where they can connect.
  - Configure the allowlist with `--egress-allowlist-file` (one domain per line; subdomains and ports are matched automatically), `--egress-allowlist` (extra inline domains merged on top), or `--egress-policy-file` (a full custom Envoy config for advanced rules). With none set, a comprehensive built-in allowlist covering common dev services (source control, package managers, registries, CDNs, cloud, AI services) is used.
  - Not supported together with `--dind` — privileged containers can bypass the firewall in the shared network namespace. New example workspaces `egress-envoy-example` and `egress-allowlist-extra-example`; complex tests under `tests/complex/test-egress-*`. See `docs/implementations/EGRESS.md`.
- **Config TUI edits package lists as multi-row fields.** Package-list parameters that accept multiple values — `apt-pkg`, `npm-pkg`, `pip-pkg`, `cargo-pkg`, `go-pkg`, `gem-pkg`, and the other `*-pkg` / install extensions — are now edited one row per package in the right panel (the same style as the Expose / Env / Mount fields on the Config tab) instead of as a single comma-joined string.
  - `↑`/`↓` move between rows; `Space`/`Enter` on **(+ add)** adds a package; `Space`/`Enter` on a package edits it; `Delete`/`Backspace` removes it; `Esc` returns to the template list.
  - Each package is stored as its own entry and compiled into a single install step (e.g. `install apt htop jq`) — equivalent to the CLI form `--select apt-pkg:htop,jq`. On save the list is deduplicated and sorted into a canonical form so the generated Boothfile is stable regardless of entry order. See `docs/BOOTH_CONFIG_TUI.md`.
- **`apt-pkg` config extension for system packages.** Debian/Ubuntu packages can now be selected through `booth config` (CLI `apt-pkg:htop,jq` or the TUI) instead of only hand-edited into the Boothfile. Supports apt's native `pkg=version` pinning and honors the `APT_SNAPSHOT` archive freeze that `booth config` stamps for reproducible builds. See `docs/BOOTH_CONFIG.md`.
- **`deno/tool` config extension** installs global Deno CLI tools via `deno install` (e.g. `deno+tool:npm:cowsay`), alongside the existing `deno/pkg` extension.
- New config-tui test suite under `tests/config-tui/` (13 scripted TUI scenarios plus shared helpers and a runner), and `install` integration tests covering every package manager under `tests/complex/test-install-*` (apt, brew, bun, cabal, cargo, conan, conda, deno, deno-pkg, gem, go, hex, luarocks, npm, pecl, pip, uv, yarn). New config tests verify each install manager has a selector extension (`test64-all-installs-have-selector`).

## 0.56.0

- **New `install apt` manager — install Debian/Ubuntu system packages from a Boothfile.** `install apt <pkg>[=<version>]` compiles to `RUN apt--install.sh ...`, alongside the existing language package managers (`install pip`, `install npm`, …). Version pins use apt's native `pkg=version` syntax. The `apt` manager auto-registers from `variants/base/setups/apt--install.sh` — no separate allowlist.
  - **Reproducible by archive snapshot.** `apt--install.sh` honors an `APT_SNAPSHOT` env var (a UTC `YYYYMMDDTHHMMSSZ` id) and passes `--snapshot` to apt, freezing the whole resolution — transitive dependencies included — to that day's Ubuntu archive (base image is Ubuntu 24.04, where `--snapshot` is auto-supported). With no `APT_SNAPSHOT`, apt resolves against the live archive as usual.
  - **`booth config` stamps the date.** Generated Boothfiles get an `env APT_SNAPSHOT=<configuration date>` line (UTC, day granularity) so rebuilds stay frozen until the next `booth config`. `CB_APT_SNAPSHOT` overrides the stamped value. See `docs/REPRODUCIBILITY.md` and `docs/BOOTH_INSTALL_APT.md`.
  - New `apt-example` workspace demonstrates `install apt` + the snapshot freeze; `clang-example` now pulls the header-only `nlohmann/json` C++ library via `install apt`. Complex tests `test-boothfile-apt` and `test-boothfile-apt-snapshot` cover both modes.

## 0.54.0

- **Native multi-arch image builds — published images are no longer cross-built under QEMU.** Each architecture is now built on a runner of that architecture, eliminating the emulation that silently broke build-time steps on the non-native arch.
  - The publish pipeline previously ran a single `buildx --platform linux/amd64,linux/arm64` on one amd64 runner, so the arm64 image was assembled under QEMU. `code-server --install-extension` fails under emulation (`Invalid ELF image`), so the codeserver build *skipped* baking its VS Code extensions (and the `.extensions-installed` marker) into the arm64 image, deferring the install to first launch on every Apple-Silicon run.
  - `docker-build.sh` gains `--arch <amd64|arm64>` (build one arch natively, push by digest) and `--merge` (assemble the per-arch digests into the multi-arch tags with `docker buildx imagetools create`, then cosign-sign). The legacy single-runner `--push` path is kept for local/standalone builds.
  - `publish-docker-images.yaml` is restructured into native per-arch matrix jobs (`ubuntu-24.04` + `ubuntu-24.04-arm`) feeding `merge` jobs: `build-base → merge-base → build-variants → merge-variants → integration-tests`. Per-arch digests pass between jobs as artifacts.
- **Fix codeserver crash on hosts whose user is not UID 1000 (e.g. macOS, where the first user is 501).** The launcher aborted with `touch: cannot touch '/usr/local/share/code-server/.extensions-installed': Permission denied`.
  - `/usr/local/share/code-server` was created at build time owned by the build-time `coder` user (UID 1000) and was not writable by other UIDs. At runtime `booth-entry` remaps `coder` to the host user's UID/GID, so the marker `touch` only succeeded when the host happened to be UID 1000 — i.e. on most Linux hosts but not on macOS. It surfaced together with the QEMU bug above, because the emulated-arch image always took the runtime (deferred) install path.
  - The shared dir is now `chmod 1777` (sticky bit, like `/tmp`) at build time so any remapped runtime UID can write the marker, and the runtime `touch "$MARKER"` is guarded with `2>/dev/null || true` so a missing optimization marker can never abort the launcher under `set -e`.
- **Removed `booth shell-config` and the host-side `booth()` shell function.** Earlier versions of the wrapper shipped a `shell-config` subcommand that wrote a `booth()` one-liner into `~/.bashrc`, `~/.zshrc`, `~/.bash_profile`, and `~/.profile`, letting users type `booth` from any subdirectory of a project. The subcommand, the function it managed, the version-marker bump mechanism, the rc-file cleanup logic, and the `--shell-config` uninstall scope are all gone. Users now always invoke `./booth` by path, or hand-write their own three-line walk-up shell function if they want a shortcut. `install.sh` and the wrapper's pipe-install bootstrap no longer touch rc files.
- Wrapper trimmed from ~1450 to ~990 lines: legacy v1–v4 rc-file cleanup awk, the `update-wrapper` subcommand, the `ALL_PLATFORMS` uninstall loop, multi-platform sha-file plumbing, and other defensive code for states the wrapper never produced are all removed.
- `booth uninstall` gets scope flags for incremental removal
  - `booth uninstall` (no flags) keeps current behavior — removes only the project binary association (`.booth/tools/` lock + sha + project-local binaries)
  - `--shared-binary` — also remove the shared-cache binary pinned by this project's lock file (`~/.cache/codingbooth/versions/<v>/`)
  - `--all-shared-binary` — also remove every version in the shared cache
  - `--wrapper` — also delete the `./booth` wrapper itself (safe self-delete on Linux/macOS)
  - `--all` — composite shorthand: shared cache (all versions) + wrapper
  - `-y` / `--yes` — skip the single all-in-one confirmation prompt; required when stdin isn't a TTY
  - All scopes compose; one prompt summarises everything before any removal happens
- `booth install` outside a project bootstraps the wrapper in the current directory
  - Running `booth` from a folder with no booth wrapper in the directory tree previously errored with a "wrapper not found" message and required the user to copy-paste a `curl ... | bash` command from the message — a natural next attempt (`booth install`) was rejected the same way
  - `booth install` now prompts "install the booth wrapper here?" then (after the wrapper lands) "install the binary now?" — two explicit confirmations, no implicit network fetch
  - `booth install -y` skips both prompts and runs `https://codingbooth.io/install.sh | bash` directly (wrapper + binary)
  - Refuses to clobber if a non-executable file named `booth` already exists in the current directory; refuses to prompt if stdin isn't a TTY (must use `-y`)
- Bash-like variable expansion for `.booth/.env`, `config.toml`, and `CB_*` env vars (see `docs/BOOTH_VARS.md`)
  - `$VAR`, `${VAR}`, `${VAR:-default}`, `${VAR:?required-message}`, leading `~`, `\$` / `\\` / `\"` / `\~` escapes, and bash-style `"..."` (expanding) / `'...'` (literal) quoting are now resolved by booth before the value reaches docker
  - `.booth/.env` and `--env-file <path>`: booth now parses the file, expands each value (earlier lines visible to later ones, falling through to host env), and hands docker a `0600` expanded copy under `.booth/.tmp/`. Docker's `--env-file` does not substitute `$VAR` or `~` natively, so without this the values were reaching the container literally
  - `${VAR:?msg}` aborts booth with a source-located error (e.g. `.booth/.env:12: required for app boot`) before any container is started, instead of producing a silent empty value
  - CLI `-e KEY=VAL` / `--env KEY=VAL` is intentionally unchanged: the invoking shell has already done its expansion, so booth does not double-expand
  - The previous `os.ExpandEnv`-based expansion (no quotes, no defaults, no errors) is replaced by `pkg/shellexpand`; existing simple `$VAR` / `~` usages keep working unchanged
- Fix UI lockup when a message title or body contains multibyte characters (em-dash, accented letters, CJK, emoji)
  - `booth-message-api-server` was setting HTTP `Content-Length` from bash's `${#body}`, which counts characters (not bytes) in a UTF-8 locale — an em-dash is 1 char / 3 bytes, so every response containing one was truncated and the browser failed to parse the JSON
  - The polling failure then triggered the lifecycle overlay's "Container stopped" guard, blanking the entire console even though the container was healthy
  - `send_response` now sends the byte count via `wc -c`
- Booth message overlay tolerates transient poll failures instead of locking the UI
  - "Container stopped" fullscreen previously fired on a single failed `/booth-messages/api/list` poll with no recovery path, even when subsequent polls succeeded
  - Threshold raised from 1 to 3 consecutive failures (~6 s at the 2 s poll interval) and the overlay auto-hides when polls resume
  - Recovery is scoped via a `data-poll-driven` marker so a deliberately-shown fullscreen (user-confirmed shutdown, `BoothPanel.showStopped`) is never auto-hidden
- ttyd terminal panes auto-reconnect on transient websocket drops
  - `start-ttyd-split` and `start-ttyd` now pass `-r 5` so the ttyd client retries every 5 seconds after a drop
  - Previously a backgrounded tab or idle timeout left a frozen pane until manual reload; the bash session inside the container survives the drop, so the reconnected ws picks up the same shell
- Pin Caddy install in `tls--setup.sh` to GitHub releases
  - `caddyserver.com/api/download` was unreachable during a build and — because the `curl` had no timeout — the `tls--setup.sh` step hung for 40+ minutes before being noticed
  - Switched to `https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz` with `CADDY_VERSION=2.11.2` pinned, `--connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5` so failures surface fast, and a tarball extract instead of a raw binary download
- Idle-timer Pause and Disable controls in the web overlay
  - Persistent `Idle:` chip in the lifecycle panel whenever `--idle-time` is armed, in three visual states: `Idle: 15m` (green, normal), `Idle: PAUSE 1h 42m` (blue, time-boxed hold with live countdown), `Idle: DISABLED` (red, pulsing — indefinite hold)
  - **Pause** = time-boxed hold that auto-resumes to normal cadence. **Disable** = indefinite hold; only cleared by Resume or a restart
  - Click the chip for a sectioned "Idle shutdown" dialog: header + description ("shuts down after X minutes... so an idle run doesn't rack up unexpected costs"), then three divider-separated sections — "Hold off for a while" (time-boxed Pause with minute input defaulted to 60), "Turn it off entirely" with danger-styled Disable button (or "Back to normal" with Resume button when already paused/disabled), and "Got it, carry on" with Close
  - Timeout "Still using this booth?" prompt shares the sectioned layout with the chip dialog — same "Hold off for a while" (Pause) + "Turn it off entirely" (Disable) sections, plus an "I'm still here" section in place of "Got it, carry on". Header shows a **live countdown** driven by the message's `expires` timestamp
  - Monitor↔overlay protocol uses semantic answer codes (`ok`, `pause:<seconds>`, `disable`) so custom-minute pauses flow through the same channel as presets
  - New API endpoints under `/booth-messages/api/idle/`: `state` (GET — returns `{enabled, idle_time, base_idle_time, shutdown_time, disabled, pause_until}`), `pause` (POST `{"seconds":N}`, capped 7d), `disable` (POST), `resume` (POST), `set-time` (POST `{"seconds":N}` — override base idle time for this session; cleared on restart)
  - "Change the timeout" section in both the chip dialog and the timeout prompt: input the new base in minutes + Apply. Monitor re-reads the effective base each loop tick so changes take effect within ~10 s
  - State persisted as ephemeral files under `.booth/.tmp/` (`.idle-disabled`, `.idle-pause-until`, `.idle-base-override`); container restart always returns to normal cadence
- Boothfile compiler skips `setup` steps the chosen variant already provides
  - `setup notebook` with `--variant notebook` (and `setup codeserver` with `--variant codeserver`) used to be re-executed on top of the variant base image, paying a full JupyterLab / code-server reinstall for nothing
  - The compiler now emits a `# skipped: ...` comment in the generated Dockerfile and a warning naming the redundant step; non-variant setups (e.g. `setup codeserver` under `--variant notebook`) still run
  - Wired through `CompilerOptions.Variant`, populated from the resolved variant at build time
- `booth_messages` Jupyter server extension removed from the notebook variant
  - All `/booth-messages/api/*` traffic has been served by the shared bash API server (via nginx) since the wrapper was introduced, so the Jupyter-side handlers were dead code
  - Notebook startup no longer logs `error adding extension (enabled: True): The module 'booth_messages' could not be found`; `booth-message-notebook-wrapped--setup.sh` now only installs the `start-notebook-wrapped` launcher
- Wrapper nginx silences JupyterLab's `/_static/out/browser/serviceWorker.js` poll
  - JupyterLab's frontend polls that path from the wrapper root every ~2 s; the file isn't served (JupyterLab is mounted at `/lab`), so every poll was flooding the container logs with 404s
  - Added a dedicated `location = /_static/out/browser/serviceWorker.js { return 204; }` rule so the poll is absorbed at nginx instead of reaching the inner server

## 0.43.0

- `booth config` TUI warns when `.booth/` directory is not writable
  - Dismissable dialog shown before TUI interaction begins
- Fix auto-select extension round-trip in config TUI
  - Auto-selected extensions (e.g. AWS Credentials) now persist across `booth config` re-opens
  - Select DSL explicitly includes all selected extensions, including auto-selected ones
  - Pre-selection correctly auto-selects extensions when loading existing config
- Fix Boothfile parsing for legacy `init`-style first-line comments

## 0.42.0

- "Container stopped" page now appears on the console (web-ttyd-split) variant
  - Previously only showed on notebook, codeserver, xfce, and kde variants
  - Detects connection loss via API poll failures and displays a fullscreen overlay
- Logout triggers container shutdown in wrapped variants (codeserver, notebook, desktop)
  - Inner service exit (e.g. user logout) now cleanly shuts down the container
  - Proper SIGTERM/SIGINT signal propagation to child processes
- Architecture documentation (`doc/ARCHITECURE.md`)

## 0.41.0

- `--idle-time <s>[,t]` — auto-shutdown after inactivity
  - Prompts "Still using this booth?" after `s` seconds of no keyboard/mouse activity
  - Auto-shuts down after `t` seconds if no response (default: 60s)
  - `--idle-exit-code <n>` — custom exit code on idle shutdown (default: 0)
  - Activity detection via browser keyboard/mouse events (throttled, once per minute)
  - Web overlay shows "Container stopped" dialog on idle shutdown
  - Works across all web variants (codeserver, notebook, xfce, kde); terminal variants shut down directly
- `--show-run-time` / `--show-count-down` — session timers in the web overlay
  - Run time: elapsed time since booth start, shown next to Restart/Shutdown buttons
  - Countdown: time remaining until auto-shutdown, with color-coded warnings at 15/10/5 min
  - `--count-down-exit-code <n>` — custom exit code when countdown expires
- `--persist-home` — persist `/home/coder` across sessions using a Docker named volume
  - `home-volume-list`, `home-volume-export`, `home-volume-import` commands
- `booth config` version setup — `--version` flag in config sets the CodingBooth version
- Desktop wallpaper branding for XFCE and KDE variants
- Renamed `booth init` to `booth config` across all code, tests, examples, and docs

## 0.40.0

- Booth message system — interactive dialogs and toast notifications inside the container
  - Message types: yes-no, ok, text, password, choice, radio, checkbox, toast
  - Web overlay with modal dialogs and auto-dismissing toasts
  - `booth--msg` terminal UI for base variant
  - HTTP API server for message create/respond
- Shutdown and restart dialogs with confirmation prompts
- Web UI overlay with lifecycle panel (Restart / Shut Down buttons)
- Fine-grained home copy with `.mount-this` markers
- `cache-dirs` template field for directory-level cache mounts
- Claude Code settings cache — persist `~/.claude/` across sessions
- Improved `booth config` TUI quit prompt
- Documentation: separate overlay and message docs

## 0.39.0

- `booth--expose` — expose container ports to the host at runtime without restarting
  - `booth--expose 8080` opens host:8080 forwarding to container:8080 via `docker exec` + `socat`
  - Works in all variants: base, terminal, codeserver, notebook, desktop
  - Supports explicit port (`8080 18080`), relative port (`8080 +8080`), and default (same port)
  - `--permanent` flag persists tunnel config to `.booth/config.toml`
  - Host-side watcher auto-detects tunnel requests via `.booth/.tmp/tcp-tunnels/` control files
- `booth--restart` — restart the booth from within the container
  - Re-reads `config.toml`, `Boothfile`, rebuilds image if needed, then launches a fresh container
  - CLI arguments from the original invocation are preserved
  - `booth--restart --yes` skips confirmation prompt
  - Works in foreground and command modes (not daemon)
  - VS Code / code-server extension: "CodingBooth: Restart" command palette entry
  - Desktop variants (XFCE, KDE) support restart via desktop actions
  - Web UI reconnects automatically after restart
- `.booth/.tmp/` ephemeral directory lifecycle
  - Wiped and recreated on every booth start, cleaned on exit
  - `booth-startup.txt` with session metadata written on each start
  - `--leave-tmp-on-exit` preserves contents for post-mortem debugging
  - `--keep-tmp-on-start` preserves leftover files from a previous session
- `--log-time` flag — prefix progress messages with timestamps (`HH:MM:SS` format)
  - Useful for debugging startup timing and tracking operation duration
  - Also settable via `CB_LOG_TIME=true` environment variable or `log-time = true` in `config.toml`
- `booth config` improvements
  - `--env`, `--expose`, and `--mount` flags for setting environment variables, port exposures, and volume mounts
  - Renamed from `booth init` — all tests and help text updated
  - First-line output and header formatting improvements
- New templates — cloud tools, databases, languages, dev tools, and AI assistants:
  - **Cloud & Infrastructure:** AWS CDK, AWS SAM CLI (with credential and DinD extensions), Azure CLI (with credential extension), Helm, kubectl (with credential extension), Terraform, Pulumi
  - **Databases:** MongoDB, Redis
  - **Languages:** .NET (replaces single dotnet template), Julia
  - **Build tools:** CMake, Gradle, SBT
  - **Dev tools:** Ansible, Conda, LazyDocker, LazyGit
  - **AI tools:** Aider, GitHub Copilot, Ollama
- Fix arm64 QEMU cross-build by deferring code-server extension installs to first launch
- `socat` added to base image for runtime port tunneling
- `install.sh` — standalone install script for easy bootstrapping
- Recipe example added to documentation
- Variant documentation improvements

## 0.37.0

- `booth config` — interactive TUI for configuring booth environments
  - Browse templates by category, select/deselect with keyboard navigation
  - Multi-tab layout: templates, config fields (variant, port, name), and preview
  - Pre-populate with `--select` flags, then fine-tune interactively
  - Edit existing `.booth/` configurations — reads Boothfile and pre-populates the TUI
  - `--no-tui` flag for headless/CI usage
- `booth shell` / `booth exec` — connect to running booths without SSH or extra ports
  - `booth shell <name>` opens a new interactive shell in a running container
  - `booth exec <name> -- <command>` runs a one-off command and returns the result
- New templates: PlantUML, Mermaid, Freeplane, Obsidian (with autostart and expose extensions)
- `no-sudo` template — revoke passwordless sudo for security hardening
- C# and F# language templates replace the single `dotnet` template
- CodeServer extensions: base, bash, and shutdown extensions now included in the notebook variant
- Test runner overhaul (`run-automate-tests.sh`)
  - Live status graph with per-suite pass/fail counts and real-time log snippets
  - `--only`, `--skip`, `--rerun-failed` flags for targeted test runs
  - Manual tests now discoverable via `run-manual-tests.sh`

## 0.36.0

- Fine-grained home copy with `.mount-this` — booth-entry now uses `smart_copy` for all four home directory seeding stages
  - Directories with `.mount-this` are copied as a unit; without it, only individual files are copied
  - Backward compatible: existing setups without `.mount-this` behave identically
  - Matches the `.booth/cache/` mount logic for consistency
- `cache-dirs` template field — create directories with `.mount-this` markers in `.booth/cache/`
  - Complementary to existing `cache-files` (which creates individual empty files)
  - Entire directory is mounted as a single bind mount into the container
- Claude Code settings cache — persist `~/.claude/` (settings, projects, memory) across sessions
  - New `settings-cache` extension (auto-selected) creates `.booth/cache/home/coder/.claude/`
  - Credential extension now mounts only `.credentials.json` via override path for fresh host credentials
  - Startup script simplified: credential seeding handled by booth-entry's `smart_copy`

## 0.35.0

- `booth build` command — build booth images and optionally push to a container registry
  - `--push <registry>` to build and push using `docker build` + `docker push`
  - `--name <name>` and `--tag <tag>` to customize the image reference
  - Content-based tagging: default tag is a 24-char SHA-256 hash of Boothfile + build-args + variant + version
  - Same configuration always produces the same tag for caching and reproducibility
  - Helpful error messages with `docker login` hints on authentication failures

## 0.32.0

- Modular startup scripts — `booth config` now generates individual files in `.booth/startups/` (e.g., `65-excalidraw-autostart--startup.sh`) instead of a single merged `startup.sh`
  - User-added `*--startup.sh` files in `startups/` survive `booth config --no-tui --overwrite`
  - Files without a `NN-` prefix default to order 50
  - Container entrypoint sorts all startup scripts by order prefix
  - Legacy `.booth/startup.sh` still supported for backward compatibility
- `--env <KEY=VALUE>` flag — pass environment variables to the container via run-args (repeatable)
- `--mount <host:container>` flag — mount volumes into the container via run-args (repeatable)
- Excalidraw template — port parameterization with `+expose` and `+autostart` extensions

## 0.31.0

- OpenSSH template — client (`openssh`) and server (`openssh+server`) with expose and credential extensions

## 0.30.0

- Fix noVNC URL in desktop variants (XFCE, KDE, LXQT) to show the actual host port instead of hardcoded container port
- Port banner now displays when a non-default port is used, not just for auto-generated ports
- Package manager templates — variadic extensions for installing global packages via `booth config`:
  npm, yarn, pip, uv, conda, cargo, go, gem, cabal, hex, luarocks, pecl, bun, brew
  (e.g., `--select nodejs+npm-pkg:express,typescript`)
- Dependency pre-installation templates — pre-install project dependencies into the Docker image at build time:
  npm-install, yarn-install, pnpm-install, bun-install, bundle-install, cargo-build, go-mod,
  mix-deps, composer-install, mvn-install, gradle-deps
  (e.g., `--select nodejs+npm-install` reads `package.json` during build, restores `node_modules` at startup)
- New example workspaces: pip-deps-example, npm-deps-example, mvn-deps-example
- New init tests for package manager templates (test30–test39)
- New init tests for OpenSSH template (test40–test44)
- Documentation: Package Management Templates section in BOOTH_INIT.md

## 0.29.0

- Booth shutdown — gracefully stop the container from within
  - `booth--shutdown` command (sends SIGTERM to all user processes)
  - VS Code / code-server extension: "CodingBooth: Shut Down" command palette entry and status-bar button
  - Shutdown button in split-view ttyd web UI with confirmation dialog
  - Desktop variants (XFCE, KDE, LXQT) detect desktop logout and shut down cleanly
- `booth template list` now shows auto-select extensions with `*` marker instead of `(auto)` suffix
- Documentation overhaul — new standalone pages: How It Works, Lifecycle, Run, Init, Examples, Home, Setup, Variants, Egress implementation
- Simplified README with links to new doc pages
- Documentation images

## 0.28.0

- New templates: DBeaver, CloudBeaver (with autostart and expose extensions), PostgreSQL, Remotion
- `booth template cat <name>` — show the raw code/content of a template
- `booth install` stays put if already installed at the requested version
- Variant showcase in README — side-by-side screenshots of Base, Notebook, Code Server, XFCE, KDE, and Bash
- Sales Explorer demo — full-stack demo with PostgreSQL, Node.js server, and Jupyter notebook
- Fix Elixir setup script
- Improved `booth` wrapper script

## 0.27.0
- More templates
- `booth template cat <name>` — show the raw code/content of a template

## 0.26.0 (unreleased)

- `booth template` command — new top-level command replacing `config list` and `config search`
  - `booth template list` — compact listing with descriptions (hides auto-select extensions)
  - `booth template search <term>` — search by name, description, or tag
  - `booth template show <name>` — detailed view with parameters, extensions, requires, tags, and file changes
  - `booth template show <name>+<ext>` — show extension details (e.g. `python+uv`)
  - `booth template show <name> --detail` — show file and segment contents
  - `--full` flag to include non-primary templates in list/search
- `booth config --set <key=value>` — set arbitrary config.toml values from the CLI (bare key = boolean true)
- `booth config --no-tui` without `--select` — create an empty booth with only CLI overrides
- `--port` flag for `config --no-tui`/`--dryrun` — set port directly in generated config.toml
- TLS support — self-signed certificate generation for HTTPS access
- Split-view ttyd — terminal split view mode
- Excalidraw template — collaborative whiteboard with autostart and expose extensions
- `.env` file support — load environment variables from `.booth/.env` at startup
- Template descriptions improved — all templates and extensions have better short and long descriptions
- Removed egress/network-whitelist configuration (simplified networking)

## 0.25.0

- Deno template with `pkg` extension for third-party module installation
- Fix `booth install` hang problem (#12)
- Fix Haskell and Deno template issues
- Fix for Windows compatibility
- Improved init security — resolver validates template dependencies
- Release version protection
- Refine templates, examples, and documentation

## 0.22.0

### Added
- `config --no-tui --overwrite` — re-generate booth configuration (overwrites existing files)
- `--version` flag for `config --no-tui`/`--overwrite`/`--dryrun` — use templates from a specific release version
- `--overwrite` flag for `config --no-tui` — overwrite existing files without prompting
- Two-line generated file header: "Generated by" (exact command) and "Adjust with" (reformatted for easy editing with `--select` last)
- `config --no-tui` path is now optional (defaults to current directory)
- `config --no-tui` allows `.booth/` to already exist; prompts for confirmation only when individual files would be overwritten

### Changed
- `booth install` downloads only the current platform's binary (not all platforms)

## 0.21.0
- Booth config, run snake and CC auto accept.

## 0.20.0
- Init templates

## 0.19.0

### Added
- `codingbooth config` command for guided project initialization
  - `config --no-tui <path>` — generate `.booth/` configuration at a target path
  - `config --no-tui --dryrun` — preview generated output without writing files
  - `--select` DSL for template selection (inline, heredoc `-`, file `@recipe`, URL `@@url`)
  - `--start` flag to immediately start the booth after config
  - `--debug` flag to inspect resolved selection and compiled output
  - `--templates-path` for local template development
  - Selection summary printed after init (templates, extensions, parameters)
  - Recipe file support for reusable selection definitions
  - Whitespace-tolerant DSL: spaces around `+` and `+` continuation lines
- Init templates: go, python, java, claude-code
  - Go extensions: vscode-ext (auto), linter
  - Python extensions: vscode-ext (auto), uv, conda
  - Java extensions: vscode-ext (auto), maven, gradle, jenv
- `uv--install.sh` — install Python packages via uv
- Example recipes in `examples/recipes/`

### Notes
- Document that `--egress` with `--dind` is **not supported** due to firewall bypass risk in the shared network namespace.

## v0.16.0
- Rename binary from `coding-booth` to `codingbooth`
- Booth example.

## v0.15.0

### Added
- Non-root package installation support -- previously only root was allowed to install packages.
    - Homebrew setup script (`homebrew--setup.sh`) for non-root package installation inside containers
    - Pip install helper script (`pip--install.sh`) for installing Python packages during image build
    - NPM install helper script (`npm--install.sh`) for installing Node.js packages during image build
    - Cargo install helper script (`cargo--install.sh`) for installing Rust packages during image build
    - Bun install helper script (`bun--install.sh`) for installing Bun packages during image build
    - RubyGems install helper script (`gem--install.sh`) for installing Ruby packages during image build
    - Deno install helper script (`deno--install.sh`) for installing Deno packages during image build

### Changed
- booth wrapper script now cache the binary per user
- booth is now location-based, meaning it operates relative to the script's own location (not the current directory) 

## v0.13.0
- Mess happens so don't have a coherent items, sorry :-p

## v0.12.0
- Rebrand fully to "CodingBooth"!!! Yeah!
- Command mode now silently forwards exit codes (no error message when commands fail)
- Add /etc/cb-home and /etc/cb-home-seed feature
- Add .booth/home and ~/.booth/home-seed feature
- Added `network-whitelist` setup for restricting container internet access to whitelisted domains

## v0.11.0
- Core engine rewritten in Go for portability (cross-platform: Linux, macOS, Windows)
- Repository restructured: `workspace/` → `variants/`, `ws` → `workspace`, CLI moved to `cli/`
- Home directory seeding via `/tmp/ws-home-seed/` for credentials
- Environment variable expansion in config.toml (`~`, `$VAR`, `${VAR}`)
- New examples: Neovim, AWS (with Jupyter notebook)
- Fixed: DinD support
- Windows compatibility, Python kernel in code-server, VNC issues
- Removed LXQT desktop variant

## v0.10.0
- Introduced the WorkSpace Wrapper (`ws`) - a stable bootstrapper script that:
  - Provides a stable entry point for using workspace
  - Automatically downloads, verifies, and launches the workspace tool
  - Handles SHA1 checksum verification for integrity
  - Supports version management and updates
- Improved build.sh - disabled signing, stopped creating bare latest/version tags
- Updated README introduction
- Reorganized release workflow

## v0.9.0
- Simplify conditional setups with CB_HAS_NOTEBOOK, CB_HAS_VSCODE and CB_HAS_DESKTOP
- Simplify the basic Dockfile structure to use ARG instead of ENV -- as it will be there anyway.
- Release to latest only when not RC
- NEXT port by default
- Print image pull/build to stderr to give the user some insight for long running commands

## v0.8.0
- Not chown in workspace-user-setup

## v0.7.0
- Default variant
- Variant alias
- Compatibilities
- Tests
- Make it work on Mac
- Verbose mode in workspace-user-setup

## v0.6.0
- Sign the image
- Change the ws-version display
- Fix ARM build problem
- Allow separate build for pushing

## v0.5.0
- Fix the path problem when running on Windows.
- Append variant and version to the image tag so it is cached locally.
- Adjust for the wrapper.

## v0.4.0
- Fix the version to each docker
- keep-alive
- Rename variants

## v0.3.0
- Rename all `*-setup.sh` to `*--setup.sh`.

## v0.2.0

### Major Updates
- Local image builds now work properly.
- Introduced a unified build script (`build.sh`).
  - Added the `--no-cache` option.
- Refactored `workspace`:
  - Modularized into clear functions and procedures.
  - First experimental implementation of **Docker-in-Docker (DinD)** via a sidecar container (attempted to isolate from the host — ultimately not fully successful).
  - Simplified configuration structure.
  - Prefixed all workspace-related environment variables with `CB_`.
  - Added `--unit-test` flag to skip running `Main()` for easier testing.
  - Added support for random or next-available port selection (`RANDOM` / `NEXT`).
- Reorganized setup scripts into **startup**, **profile**, and **starter** stages.
- Removed PowerShell support (maintenance overhead too high).
- Added multiple example configurations:
  - `dind`
  - `go`
  - `java`
  - `jetbrain`
  - `nodejs`
  - `python`
  - `server`

### Supported Variants
- **Base**
- **Notebook**
- **CodeServer**
- **Desktop**
  - XFCE
  - KDE

### Supported Setups
- `brew`
- `chromium-browser`
- `codeserver`
- `dind`
- `docker-buildx`
- `docker-compose`
- `eclipse`
- `firefox`
- `google-chrome`
- `go`
- `gradle`
- `idea`
- `jdk`
- `jenv`
- `jetbrains`
- `kde`
- `lxqt`
- `mvn`
- `nodejs`
- `notebook`
- `pycharm`
- `python`
- `template`
- `variant`
- `vscode`
- `xfce`

### Supported Notebook Kernels
- `bash-nb-kernel`
- `java-nb-kernel`

### Supported Code Extensions
- `bash-code-extension`
- `go-code-extension`
- `java-code-extension`
- `jupyter-code-extension`
- `python-code-extension`
- `react-code-extension`

### Supported Notebook Plugins
- `jetbrains-plugin`
- `lombok-eclipse`
