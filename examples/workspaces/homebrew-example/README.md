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

### Run it

```bash
just --list
just test                # check all nine brew tools, one script each
just packages            # brew list --versions of the formulae installed on request
just services            # a throwaway PostgreSQL, Redis and nginx — start, query, stop
just bat                 # this README through bat
```

The checks are the scripts in `.cb-tests/`, so `just test` is the same run the example's own test
does.

## What's included

| Component | Details                                                                  |
|-----------|--------------------------------------------------------------------------|
| Manager   | Homebrew                                                                 |
| Packages  | `bat`, `neovim`, `imagemagick`, `node`, `ffmpeg`, `gcc`, `postgresql`, `redis`, `nginx` |

Edit the `install brew ...` line in `.booth/Boothfile` to add or remove packages.
