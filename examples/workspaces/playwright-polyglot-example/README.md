# Playwright Polyglot Example — one browser, five languages

The same Playwright script, written in **JavaScript, Python, Java, C#/.NET, and Go**,
all driving the **same pinned Chromium** — the one pre-baked into the booth image. Each
one opens **its own language's official website**, saves a screenshot to
`shots/<language>.png`, runs a little JavaScript inside the browser (summing 1..10), and
prints `TITLE|SUM` — the live page's title, and `55` as proof it executed JavaScript in
the page. Five languages, one browser, five real screenshots.

This is the point Playwright makes that's easy to miss: the browser is the hard,
environment-sensitive part, and it is **managed and version-pinned by Playwright itself**.
The four official bindings (JS, Python, Java, .NET) are all pinned to Playwright 1.58 and
**share one Chromium** in `~/.cache/ms-playwright`. Go uses the community
`playwright-go` binding, which pins its own driver version and so brings its own browser.

**Stack:** Node.js, Python, JDK + Maven, .NET SDK, Go · Playwright (Chromium) pinned to 1.58.0

## Run

```bash
./booth -- ./run-polyglot.sh
```

That runs all five and prints a summary:

```
==================== SUMMARY ====================
  JavaScript   PASS   "JavaScript | MDN"          [shots/javascript.png, ... bytes]
  Python       PASS   "Welcome to Python.org"     [shots/python.png, ... bytes]
  Java         PASS   "java.com: ..."             [shots/java.png, ... bytes]
  C#           PASS   "The C# language ..."       [shots/csharp.png, ... bytes]
  Go           PASS   "The Go Programming ..."    [shots/go.png, ... bytes]
=================================================
```

Each language leaves a screenshot of its own official site in `shots/` — five real
pages, one pinned browser. The pages each language visits:

| Language | Page |
|----------|------|
| JavaScript | https://developer.mozilla.org/en-US/docs/Web/JavaScript |
| Python | https://www.python.org/ |
| Java | https://www.java.com/en/ |
| C#/.NET | https://dotnet.microsoft.com/en-us/languages/csharp |
| Go | https://go.dev/ |

Override any single one with `PAGE_URL`, e.g. `./booth -- bash -c 'cd python && PAGE_URL=https://docs.python.org/ python check.py'`.

Run a single language on its own:

```bash
./booth -- bash -c 'cd js     && node check.js'
./booth -- bash -c 'cd python && python check.py'
./booth -- bash -c 'cd java   && mvn -q compile exec:java'
./booth -- bash -c 'cd csharp && dotnet run'
./booth -- bash -c 'cd go     && go run check.go'
```

## What's inside

| Language | Binding | Pinned to | Browser |
|----------|---------|-----------|---------|
| JavaScript | `playwright` (npm) | 1.58.0 | shared pre-baked Chromium |
| Python | `playwright` (pip) | 1.58.0 | shared pre-baked Chromium |
| Java | `com.microsoft.playwright` (Maven) | 1.58.0 | shared pre-baked Chromium |
| C#/.NET | `Microsoft.Playwright` (NuGet) | 1.58.0 | shared pre-baked Chromium |
| Go | `playwright-community/playwright-go` | own driver | its own Chromium |

- `js/`, `python/`, `java/`, `csharp/`, `go/` — one small program per language, each
  doing the identical task against its own URL.
- `run-polyglot.sh` — runs all five and prints the summary.
- `.booth/Boothfile` — installs the five toolchains and pre-bakes the pinned Chromium.
  Project dependencies (npm / pip already baked, Maven / NuGet / Go modules) resolve on
  first run.

## How it works

The booth image bakes the toolchains and the pinned Chromium once. The official bindings
reuse that browser because they're pinned to the matching Playwright version — so there's
one browser download in the image, not five. The Go binding is community-maintained and
tracks its own driver release, so it installs a browser of its own the first time it runs.

> Demo only. The first run resolves each ecosystem's dependencies (Maven, NuGet, Go
> modules) and — for Go — downloads a browser, so it needs outbound network and takes a
> while; later runs are fast.
