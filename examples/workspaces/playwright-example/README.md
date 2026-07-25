# Playwright Example

This example is a ready-to-run browser-automation environment built on Playwright and headless Chromium. `run-playwright.sh` runs the sample Playwright test suite and `run-screenshot.sh` drives Chromium to a real page (Hacker News by default) and saves a screenshot, using the browser already baked into the image. Node.js, Playwright, and a version-pinned Chromium are baked into the booth image up front, so the first test run is as fast as the hundredth — no multi-hundred-megabyte browser download, no flaky "installing Chromium" step that stalls behind a proxy or on a fresh CI runner. Every developer and every pipeline drives byte-for-byte the same browser build, which is the difference between "works on my machine" and screenshots that actually match. It's browser automation that's reproducible and offline-ready out of the box.

**Stack:** Node.js 22, Playwright, Chromium

## Quick start

```bash
# 1. Launch the booth (the playwright setup pre-installs browser binaries)
cd examples/workspaces/playwright-example
booth

# 2. Inside the booth — run the test suite
./run-playwright.sh

# 3. Or capture a screenshot of a real web page
./run-screenshot.sh                              # defaults to Hacker News
./run-screenshot.sh https://playwright.dev shot.png
```

Both scripts run `npm ci` first (project deps are git-ignored). The Chromium
build is pre-baked into the booth image — pinned to the same Playwright version
the project uses — so **nothing is downloaded at runtime**.

## What's included

| Component       | Details                                            |
|-----------------|----------------------------------------------------|
| Runtime         | Node.js 22                                         |
| Browser         | Chromium (via Playwright), headless                |
| VS Code support | Playwright + Node.js extensions                    |
| Sample          | `tests/` with `playwright.config.ts`               |
| Screenshot demo | `screenshot.js` + `run-screenshot.sh`              |

Override the browser set via the `PLAYWRIGHT_BROWSERS` build arg in `.booth/Boothfile` (e.g. `firefox` or `webkit`), and the version via `PLAYWRIGHT_VERSION`.

> Note: some sites (e.g. reddit.com) block headless browsers and return a
> "blocked by network security" page instead of content. Hacker News and
> `playwright.dev` render fully.
