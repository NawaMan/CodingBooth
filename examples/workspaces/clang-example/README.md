# Clang Example

This example is a C/C++ development environment with the LLVM/Clang toolchain and CMake. `src/primes.cpp` runs a prime sieve and, in `--json` mode, serializes the primes with the apt-installed `nlohmann/json` library, built via CMake and Make. Reproducibility: the LLVM/Clang version and the apt archive are pinned, so the toolchain and libraries stay deterministic across rebuilds. C++ builds are notoriously sensitive to which compiler and which library headers happen to be on a machine — pin both and "works on my machine" stops being a gamble. Rebuild next month or on a colleague's laptop and you get the identical Clang major and the identical `nlohmann/json`, so a green build today stays a green build tomorrow.

**Stack:** Clang/LLVM, CMake, Make

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/clang-example
booth

# 2. Inside the booth — build and run the demo
./run-primes.sh 20
./run-primes.sh --json 20   # same primes, serialized with the apt-installed JSON library
```

## What's included

| Component   | Details                                                        |
|-------------|----------------------------------------------------------------|
| Compiler    | Clang/LLVM (default version 18)                                |
| Build       | CMake + Make                                                   |
| C++ library | `nlohmann/json`, installed with `install apt nlohmann-json3-dev` |
| Sample      | `src/primes.cpp` — prime sieve, with a `--json` output mode     |

The `LLVM_VERSION` build arg in `.booth/Boothfile` lets you pin to a different LLVM major.

## Installing a C++ library with apt

The `.booth/Boothfile` adds a system library the same way it adds the toolchain:

```
install apt nlohmann-json3-dev
```

`nlohmann-json3-dev` is header-only — apt drops `/usr/include/nlohmann/json.hpp` onto the
default include path, so `src/primes.cpp` just does `#include <nlohmann/json.hpp>` with no
linking and no CMake `find_package`. `./run-primes.sh --json 20` then prints the primes as
a JSON array via the library.

Pin a version with apt's native syntax (`install apt nlohmann-json3-dev=3.11.3-1`), and
freeze the whole archive reproducibly by adding an `env APT_SNAPSHOT=<id>` line above the
`install` — see the [apt-example](../apt-example/) workspace and
[REPRODUCIBILITY.md](../../../docs/REPRODUCIBILITY.md#apt--pin-the-snapshot-not-the-package).
