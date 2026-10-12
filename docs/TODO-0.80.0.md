Proposal

P1. Make git work in booths started from a git worktree. (high impact)
- Problem: CodingBooth's own agent workflow is worktree-based, but inside such a booth git status, gh, committing from Claude Code, and any gate step calling git ls-files all fail. That broke cargo xtask ci in 8 of 9 projects.
- Diagnostic: the changelog already says a worktree booth starts but git doesn't work, because the real git folder (git rev-parse --git-common-dir) lives in the main clone, outside the mount.
- Approach: when .git is a gitfile, also mount the main clone's git folder at its own absolute path. That's the same repository the booth already writes to, so it shouldn't trigger the consent prompt; worth a line in BOOTH_SECURITY.md. Same treatment for submodules.

P2. Stop duplicate desktop viewers from fighting. (high impact; this was the flicker)
- Problem: every exec --run / shell --run that starts a booth opens a browser tab. Two tabs on one desktop each resize it to fit their own window, so the screen jumps back and forth.
- Approach:
  - don't open the browser for exec --run, shell --run or -- command mode by default; they're terminal commands;
  - in the noVNC page, only one viewer gets to resize the desktop, and the others scale to fit;
  - drop the export CB_BROWSER := "false" workaround from the just-init starter once this lands.

P3. Start without the registry when nothing has changed. (high impact)
- Problem: during a Docker Hub auth outage (500/504 errors), a booth whose image was already built still wouldn't start, because every start runs docker build, and that contacts Docker Hub for the docker/dockerfile:1.7 frontend.
- Approach: fingerprint the generated Dockerfile plus the copied inputs (.booth/setups/, the toolchain files). If an image with that fingerprint exists, skip the build. Also pin the frontend by digest.

P4. Apply the Homebrew/Rust environment fix to the rest of the catalog.
- Problem: 20 more setups set PATH or *_HOME only in /etc/profile.d, which booth exec never reads: affine-server, anythingllm, clang, cloudbeaver, cmake, conda, deno, dotnet, flutter, gcc, go, gradle, hoppscotch, jdk, julia, make, penpot, ruby, sbt, selenium. Some symlink their binaries so they half-work. (That's from a quick grep, not a reproduction.)
- Approach: move those exports into template env lines, plus a catalog guard test that fails when a setup's profile exports something its template doesn't put on the image environment.

P5. Make GUI apps work from booth exec on desktop variants.
- Problem: exec has no DISPLAY, and exec --run returns before the X server is up. Every GUI recipe needed a wait loop.
- Approach: desktop variants set DISPLAY=:1 on the image environment, and exec --run waits for the desktop health check before running the command.

P6. A Rust desktop-app recipe and a Rust-aware just-init.
- Problem: the same selection and the same Justfile, assembled nine times.
- Approach:
  - a recipe @rust-desktop (desktop-xfce, rust with wasm32, gui-deps, trunk, gh), selectable as --select @rust-desktop/claude-code+…;
  - just-init detects Cargo.toml and writes build/test/run/clippy recipes, plus ci when it finds cargo xtask and web when it finds a Trunk.toml;
  - run gets the display handling from P5 for free.

P7. Support scripts copied from a newer CodingBooth. (low priority)
- Moved to docs/TODO.md as a "to relook later" item (booth vendor).

P8. Smaller booth config fixes, all hit during setup:
- --set on a list appends silently, and the appended value isn't recorded in the Boothfile header, so the next regeneration doesn't reproduce the file. A comma isn't treated as a list separator. There's no --unset. --remove-env NAME=value silently does nothing.
- Approach: --set replaces lists and is always recorded in the header; add --unset; commas split lists; a remove that matches nothing is an error.

P9. Small improvements:
- treat "removal already in progress" as success when tearing down after exec --run; it prints a scary-looking warning on almost every run;
- consider making port = "NEXT" the default for desktop variants, since a fixed 10000 collides as soon as two booths run;
- add an optional rust+sccache extension so builds share compiled crates across projects. Nine target/ folders at 10–30 GB each adds up.

Suggested order

- First: P1, P2 and P3. Each is small and hits every project, not just Rust.
- Next: P4 and P5. One sweep each, with guard tests so they stay fixed.
- Then: P6, which builds on P5.
- Later: P8, and P7 (moved to docs/TODO.md).
