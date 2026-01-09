# TODO

This is where dreams begin. ✨  
A list of upcoming ideas, improvements, and future goals for the workspace launcher.

---

## Core Features
- [X] Add TESTS, add TESTS, add TESTS, add TESTS!!!
- [-] Remove CVEs -- give up
- [X] Try to not have "user-land" setup print anthing (unless error) -- nodejs-example
- [ ] Improve Docker-in-Docker (DinD) integration — ideally without relying on a sidecar container.
- [ ] Add Kubernetes (K8s) support.
- [ ] Support non-X11 environments (e.g., Unity, Omarchy, Wayland).
- [-] Rename “variant” to “interface” for clarity: -- NOTE: `variant` is good.
- [ ] Add desktop icons for IDEs (e.g., VS Code, JetBrains IDEs).
- [-] Simplify adding Jupyter Notebooks to desktop environments (auto-add like VS Code).
- [ ] Evaluate using host disk or tmpfs (RAM) for `$HOME` to improve I/O performance.
- [X] Deprecate one of `KDE` or `LXQt` to reduce maintenance complexity.
- [ ] Improve container startup speed — some setup tasks run too early (in `STARTUP`).
- [ ] See if we can sync the setup with GitHub action (just seen it recently that it exists)
- [ ] Install jpterm - for all variants. https://github.com/davidbrochart/jpterm
- [ ] Install yazi CLI file browser - for all variants. https://lindevs.com/install-yazi-on-ubuntu
- [ ] Change to use JJava instead of IJava. https://github.com/dflib/jjava
- [ ] Add symbolic link to go install directory.
- 

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

