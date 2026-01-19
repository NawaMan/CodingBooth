# TODO

This is where dreams begin. ✨  
A list of upcoming ideas, improvements, and future goals for the workspace launcher.

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
- [ ] Support non-X11 environments (e.g., Unity, Omarchy, Wayland).
- [-] Rename “variant” to “interface” for clarity: -- NOTE: `variant` is good.
- [ ] Add desktop icons for IDEs (e.g., VS Code, JetBrains IDEs).
- [-] Simplify adding Jupyter Notebooks to desktop environments (auto-add like VS Code).
- [ ] Evaluate using host disk or tmpfs (RAM) for `$HOME` to improve I/O performance.
- [X] Deprecate one of `KDE` or `LXQt` to reduce maintenance complexity.
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
- [ ] ...

## Problems
- [ ] VS Code hangs sometimes.
- [ ] Java example: Lombok does not work in VS Code.
- [ ] ...

---

## Additional Setups
Add or improve support for these developer tools and environments:

- [ ] `aws-cli`
- [ ] `az-cli`
- [ ] `bun`
- [ ] `clang`
- [ ] `cmake`
- [ ] `conda`
- [ ] `deno`
- [ ] `docker`
- [ ] `dotnet`
- [ ] `elixir`
- [ ] `erlang`
- [ ] `gcc`
- [ ] `gcloud`
- [ ] `go`
- [ ] `haskell`
- [ ] `julia`
- [ ] `k8s-local`
- [ ] `kafka`
- [ ] `kotlin`
- [ ] `kubectl`
- [ ] `lua`
- [ ] `make`
- [ ] `mongodb`
- [ ] `mysql`
- [ ] `nodejs`
- [ ] `ocaml`
- [ ] `php`
- [ ] `postgres`
- [ ] `rabbitmq`
- [ ] `roc`
- [ ] `r-rscript`
- [ ] `ruby`
- [ ] `rust`
- [ ] `sbt`
- [ ] `scala`
- [ ] `swift`
- [ ] `zig`

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

