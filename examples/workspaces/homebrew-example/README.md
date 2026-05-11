# Homebrew Example

Demonstrates installing extra command-line tools via [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux) on top of the base booth.

**Stack:** Homebrew (Linuxbrew), curated set of brew packages

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/homebrew-example
booth

# 2. Inside the booth — try one of the brew-installed tools
bat README.md
nvim
```

## What's included

| Component | Details                                                                  |
|-----------|--------------------------------------------------------------------------|
| Manager   | Homebrew                                                                 |
| Packages  | `bat`, `neovim`, `imagemagick`, `node`, `ffmpeg`, `gcc`, `postgresql`, `redis`, `nginx` |

Edit the `install brew ...` line in `.booth/Boothfile` to add or remove packages.
