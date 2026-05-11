# Playwright Example

A browser-automation testing environment with [Playwright](https://playwright.dev) and headless Chromium.

**Stack:** Node.js 22, Playwright, Chromium

## Quick start

```bash
# 1. Launch the booth (the playwright setup pre-installs browser binaries)
cd examples/workspaces/playwright-example
booth

# 2. Inside the booth — run the test suite
./run-playwright.sh
```

## What's included

| Component       | Details                                            |
|-----------------|----------------------------------------------------|
| Runtime         | Node.js 22                                         |
| Browser         | Chromium (via Playwright)                          |
| VS Code support | Playwright + Node.js extensions                    |
| Sample          | `tests/` with `playwright.config.ts`               |

Override the browser set via the `PLAYWRIGHT_BROWSERS` build arg in `.booth/Boothfile` (e.g. `firefox` or `webkit`).
