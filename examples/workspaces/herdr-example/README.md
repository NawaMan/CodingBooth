# Herdr Example

This example is a booth that bundles Herdr — an agent multiplexer, "tmux for AI agents" — together with a pinned clang/LLVM toolchain. Its `.booth/Boothfile` installs Herdr and Claude Code on top of a pinned clang/LLVM 18 toolchain in a terminal variant, ready to run and coordinate coding agents. A niche tool like Herdr and a version-pinned clang/LLVM toolchain arrive batteries-included from a single selector, so nobody has to hunt down a release binary, match a compiler version, or write install docs that rot. Everyone who opens the booth gets the identical Herdr build on the identical LLVM 18, ready to orchestrate coding agents against a C/C++ project from the first second. That's the whole point of a booth: name the tools once, and a reproducible environment materializes with no manual setup.

## Quick start

```bash
cd examples/workspaces/herdr-example
./booth      # a bash shell in the booth (terminal variant)
herdr        # inside it: start Herdr
```

### Run it

```bash
just --list
just versions            # herdr, claude and clang versions
just hello               # compile and run a one-line C++ program with clang++ 18
just herdr               # Herdr in the booth (from the host)
```

Herdr is a full-screen terminal app, so `just herdr` runs it through `booth exec --it`, which gives
it a terminal. Inside the booth, just type `herdr`.
