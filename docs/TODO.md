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
- [ ] VS Code hangs sometimes.
- [ ] **Jupyter Notebook (`.ipynb`) in VS Code hangs on cell execution.** In the desktop
      variants (and anywhere the bundled VS Code opens a notebook), the VS Code Jupyter
      extension (`ms-toolsai.jupyter`) hangs when running cells. Matches upstream
      [vscode-jupyter#17228](https://github.com/microsoft/vscode-jupyter/issues/17228)
      ("ipykernel 7 causes notebook execution to hang"); the fix, PR #17411, is a stalled,
      unmerged draft, so no released extension version fixes it.
      Investigation so far:
      - The kernel itself is healthy — it starts and executes fine over a native
        `jupyter_client` connection, so ports/kernelspecs/ZeroMQ-native are not the issue.
      - The image shipped `ipykernel` **7.3.0** (installed unpinned). Its `kernel.json`
        carries ipykernel-7-only fields (`supported_encryption: "curve"`,
        `kernel_protocol_version: "5.5"`).
      - Pinned `ipykernel>=6,<7` in `notebook--setup.sh`, `vscode--setup.sh`, and
        `python-nb-kernel--setup.sh` as a precaution (matches upstream guidance).
      - **BUT: downgrading a live booth to ipykernel 6.31.0 (fields gone, kernel healthy)
        did NOT clear the hang.** So ipykernel 7 is not the (whole) root cause — the pin is
        a mitigation, not a fix. Real cause still unknown.
      Next steps: capture the extension's live logs *while a cell is actually running*
      (not just the session header); check `@vscode/zeromq` native module load in the
      extension host; consider a VS Code 1.128 / extension-version interaction. Workaround
      today: use the browser-based `notebook` variant for notebooks.
- [ ] Java example: Lombok does not work in VS Code.
- [ ] `remove`/`stop`/`start`/`restart` ignore flags placed *after* the positional name (e.g. `booth remove myproj --force` does not force) because they use plain `flag.Parse`, which stops at the first positional. `shell`/`exec` already work around this with `extractPositionalAndFlags`; apply the same handling to the other lifecycle commands so flag order doesn't matter.
- [ ] ...

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

