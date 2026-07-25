# Homebrew Example

This example installs extra command-line tools via [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux) on top of the base booth. A single `install brew` line brings in a curated set — bat, neovim, imagemagick, node, ffmpeg, gcc, postgresql, redis, and nginx. Host stays clean: this big Linuxbrew tool set installs inside the booth, leaving nothing on your host's brew prefix. Pull in nine substantial packages — databases, media tools, a compiler — without a single formula landing in your host's `/home/linuxbrew` or tangling with what you've already brewed. It's a disposable, self-contained brew environment: use it, share it, and delete it with zero residue on your machine.

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
