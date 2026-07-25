# TODO

This is where dreams begin. ✨  
A list of upcoming ideas, improvements, and future goals for the CodingBooth launcher.

---

## Code Features
- [ ] We might want to flip the docker chain if we want to make it start faster.
      Right now, Project -> Variant -> Base ... but users of the same project may choose different variants. So all the setup such as language, framework, libraries, tools, etc. will be done last.
      That is when people change variants, they will have to re-run the setup.
- [ ] Figure out a way to separate setups from the base variant.
- [ ] Add "previous" variable - e.g., use for continue (for --keep-alive) and previous variant can be useful to speed things up.
- [ ] ...

## Features
- [x] Add TESTS, add TESTS, add TESTS, add TESTS!!!
- [-] Remove CVEs for docker images -- give up (most found in core pages like python, nodejs, etc)
- [x] Try to not have "user-land" setup print anthing (unless error) -- nodejs-example
- [x] Improve Docker-in-Docker (DinD) integration — ideally without relying on a sidecar container.
- [x] Add Kubernetes (K8s) support.
- [~] Support non-X11 environments (e.g., Unity, Omarchy, Wayland). -- `desktop-wayland` variant adds a Wayland-native labwc desktop (wlroots) over wayvnc+noVNC. (Real GNOME-on-Wayland attempted via WebRTC but blocked by headless mutter frame emission; parked on branch wip/desktop-gnome-webrtc.)
- [-] Rename “variant” to “interface” for clarity: -- NOTE: `variant` is good.
- [ ] Add desktop icons for IDEs (e.g., VS Code, JetBrains IDEs).
- [-] Simplify adding Jupyter Notebooks to desktop environments (auto-add like VS Code).
- [ ] Evaluate using host disk or tmpfs (RAM) for `$HOME` to improve I/O performance.
- [ ] Improve container startup speed — some setup tasks run too early (in `STARTUP`).
- [ ] See if we can sync the setup with GitHub action (just seen it recently that it exists)
- [X] Install jpterm - for all variants. https://github.com/davidbrochart/jpterm
- [-] Install yazi CLI file browser - for all variants. https://lindevs.com/install-yazi-on-ubuntu
- [x] Change to use JJava instead of IJava. https://github.com/dflib/jjava
- [X] Add template repository.
- [ ] Add example repository.
- [ ] Firebase example does not work because home seed will not copy the file if exist but FB creates empty JSON file -- "{}" there.
Need to find a way to fix this. This may involve creating a different type of home seed that will overwrite the file if exist.
- [ ] Report container with the same name exists better. Also suggest how to remove the container.
- [ ] SAVE (--keep-alive)/LOAD (continue)/EXPORT (save to file)/IMPORT (load from file) 
- [ ] Add more tip to 99z-cb-profile.sh - Like those functions after setups (python-info, start-xfce and etc.)
- [ ] Consider using ubuntu-keyring instead of debian-archive-keyring.
- [ ] Add `booth-help` command inside the container to show available tools and commands.
- [ ] Polish the `booth config` hand-off for hand-written files. The feature itself is **done** and is
      deliberately as far as we go: a hand-written `.booth/Boothfile` is protected, `--beside` (or Enter
      in the TUI) keeps it and writes the generated content as `Boothfile.new`, and we print a `diff`
      command. Producing the two files is our job; merging them is the user's. Two cosmetic gaps:
      - Printed paths are absolute and long — print them relative to the cwd so the command is easy to
        copy-paste.
      - `diff` only *shows* the difference. Also suggest a side-by-side merge (`vimdiff`, `code --diff`).

      **Rejected — do not re-propose (investigated 2026-07-11):**
      - *Storing the last-generated content as a merge base, for a three-way merge.* It does not earn its
        keep. Boothfiles are tiny (largest in repo: 50 lines; average ~8), so a two-way diff is readable
        by hand and three-way saves roughly one hunk. Worse, the base does not exist for the dominant
        case — 230 of 301 tracked booth files are hand-written from scratch and never had a generated
        predecessor — so the machinery would only help the minority. The "extra hunks" a two-way diff
        shows are not noise; they are exactly the changes the user just asked for in the TUI. Costs:
        changes the `.booth/.generated` format, needs diff3 (no Go stdlib; repo runs on 2 deps), and adds
        an adoption trap — adopting a hand-edited legacy file as its own base makes a later merge *delete*
        the user's edits.
      - *Reading the Boothfile back into TUI state so the TUI can represent everything.* Impossible as a
        total function: the Boothfile DSL (`run`, `copy`, `workdir`, arbitrary shell) is strictly richer
        than the TUI's vocabulary (template selections + params), so a hand-written `run echo hi` has no
        template preimage. (Measured: ~99% of *generated* lines can be attributed back to a template
        segment, because the compiler emits segments verbatim. So a read-only "custom directives,
        preserved verbatim" panel would be feasible — if it is ever actually wanted.)
- [ ] ...

## Problems
- [ ] VS Code hangs/crashes sometimes. Some cases were the 64 MB `/dev/shm` renderer crash
      fixed below (`code: 133`); watch for any that survive that fix.
- [x] **Jupyter Notebook (`.ipynb`) in VS Code hangs/crashes.** RESOLVED 2026-07-14.
      The earlier ipykernel-7 / [vscode-jupyter#17228] theory was **wrong**. Verified on a
      live `desktop-xfce` booth:
      - Desktop VS Code and `code-server` run the **same** Jupyter extension (2025.9.1) and
        the **same** ipykernel (6.31.0), yet only desktop VS Code failed — so the extension
        version was never the difference. The `ipykernel>=6,<7` pins were mitigating a cause
        that wasn't the cause; they have been removed.
      - The kernel is healthy: it executes over a native `jupyter_client` connection (`ok`).
      - The real failure is an **Electron renderer crash** —
        `CodeWindow: renderer process gone (reason: crashed, code: 133)` in `main.log`. The
        container's `/dev/shm` defaults to **64 MB**, and Chromium's renderer maps its shared
        memory there (confirmed: renderer processes hold fds into `/dev/shm`). Rendering a rich
        notebook (embedded images/widgets) overflows 64 MB and the renderer aborts.
      - `code-server` is immune — it renders in the **host** browser, which has a normal-sized
        `/dev/shm`. Bash/Java notebooks survived because their text output stays small.
      Fix (two complementary changes):
      - `vscode--setup.sh`: the `code` wrapper now passes `--disable-dev-shm-usage`, so Chromium
        puts its shared memory under `/tmp` (223 GB free) instead of `/dev/shm`. Verified: with
        the flag the renderer processes hold 0 fds into `/dev/shm` (4 under `/tmp` instead).
      - Desktop variants now run with `--shm-size=1g` (`PrepareCommonArgs`, gated on
        `HasDesktop`), which also protects the desktop's web browser and any other
        Chromium/Electron app, not just VS Code.

[vscode-jupyter#17228]: https://github.com/microsoft/vscode-jupyter/issues/17228

- [ ] Java example: Lombok does not work in VS Code.
- [ ] `remove`/`stop`/`start`/`restart` ignore flags placed *after* the positional name (e.g. `booth remove myproj --force` does not force) because they use plain `flag.Parse`, which stops at the first positional. `shell`/`exec` already work around this with `extractPositionalAndFlags`; apply the same handling to the other lifecycle commands so flag order doesn't matter.
- [ ] ...

---

## Binary companions (libraries that need a separate tool binary)

Libraries whose package install alone is not enough — they also need a companion
CLI or engine (`protoc`, parser generators, ffmpeg, graphviz, browser drivers,
ORM CLIs, …). C/C++ `lib-*` / `*-dev` is a separate track.

Full audit and priority shortlist: **[TODO-BINARY_COMPANIONS.md](TODO-BINARY_COMPANIONS.md)**.

- [x] Phase 1 — TUI templates: `protobuf` (+ Go plugins), `buf`, `ffmpeg`, `graphviz`
- [x] Phase 2 — `dotnet-pkg` (`install dotnet` / `csharp+dotnet-pkg:dotnet-ef`)
- [x] Phase 3 — Puppeteer / Cypress / Selenium stacks
- [x] Phase 4 — Docs “library X → also select Y” ([BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y))

---

## Additional Setups
Add or improve support for these developer tools and environments:

- [x] `network-whitelist` - Restrict container internet access to whitelisted domains
- [x] `aws-cli`
- [x] `az-cli` (azure-cli)
- [x] `bun`
- [ ] `clang`
- [ ] `cmake`
- [x] `conda`
- [x] `deno`
- [x] `docker` (dind)
- [x] `dotnet`
- [x] `elixir`
- [x] `erlang`
- [ ] `gcc`
- [x] `gcloud`
- [x] `go`
- [x] `haskell`
- [ ] `julia`
- [x] `k3d`
- [x] `k9s`
- [ ] `kafka`
- [x] `kind`
- [x] `kotlin`
- [x] `kubectl`
- [x] `kubectx` + `kubens`
- [x] `lua`
- [ ] `make`
- [ ] `mongodb`
- [x] `mysql`
- [x] `nodejs`
- [ ] `ocaml`
- [x] `php`
- [x] `postgres`
- [ ] `rabbitmq`
- [ ] `roc`
- [x] `r-rscript`
- [x] `ruby`
- [x] `rust`
- [ ] `sbt`
- [x] `scala`
- [ ] `swift`
- [x] `zig`
- [x] `terraform`
- [x] `helm`
- [x] `aws-sam-cli`
- [x] `aws-cdk`
- [x] `gh-copilot`

---

## Code Extensions
- [ ] Add code extensions for each supported setup (e.g., language-specific IDE plugins or VS Code extensions).

---

## Notebook Kernels
Add or expand support for additional Jupyter Notebook kernels:

- [ ] **PySpark** – Run Python code interacting with Apache Spark.
- [ ] **TensorFlow / PyTorch kernels** – Preloaded for machine learning frameworks.
- [ ] **IRkernel** – R language kernel, popular for data analysis and statistics.
- [ ] **Julia (IJulia)** – High-performance computing and numerical analysis.
- [ ] **SageMath** – Symbolic mathematics with the SageMath system.
- [ ] **Octave** – MATLAB-like numerical computing.
- [ ] **IHaskell** – Interactive Haskell programming.
- [ ] **C++ (xeus-cling)** – Interactive C++ kernel.
- [ ] **Node.js (IJavascript)** – Run JavaScript in Jupyter.
- [ ] **Ruby (IRuby)** – Enable Ruby scripting.
- [ ] **SQL** – Execute SQL queries directly within notebooks.
- [ ] **MATLAB** – Integrate MATLAB code execution.
- [ ] **Fortran** – Support for scientific computing with Fortran.

