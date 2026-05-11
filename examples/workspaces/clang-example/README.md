# Clang Example

C/C++ development environment with the LLVM/Clang toolchain and CMake.

**Stack:** Clang/LLVM, CMake, Make

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/clang-example
booth

# 2. Inside the booth — build and run the demo
./run-primes.sh 20
```

## What's included

| Component | Details                              |
|-----------|--------------------------------------|
| Compiler  | Clang/LLVM (default version 18)      |
| Build     | CMake + Make                         |
| Sample    | `src/primes.c` — prime number sieve  |

The `LLVM_VERSION` build arg in `.booth/Boothfile` lets you pin to a different LLVM major.
