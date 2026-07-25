# Kotlin Example

This example is a Kotlin workspace that compiles to a runnable JAR, paired with a matched JVM and a Kotlin notebook kernel for exploration. The bundled `Fibonacci.kt` takes a count and prints that many numbers of the Fibonacci sequence, labeling each one as `F(index) = value`. The quiet win here is version compatibility done right: the Kotlin compiler and the Temurin JDK are pinned to releases that are known to agree. Kotlin is picky about which JVM bytecode targets it supports, and a mismatched compiler and JDK surfaces as baffling "unsupported class file version" or target errors that have nothing to do with your code. This booth removes that whole failure class — and because both versions are overridable via `KOTLIN_VERSION` and `JDK_VERSION` build args, you can bump either one deliberately while still starting from a known-good pairing.

**Stack:** Kotlin 2.0, JDK 21 (Temurin), Python 3.13, Jupyter, XFCE desktop, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/kotlin-example
booth

# 2. Inside the booth — compile and run
./run-fibonacci.sh 10
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Language        | Kotlin (default 2.0.20)              |
| JVM             | Temurin JDK 21                       |
| Notebook        | Jupyter + Kotlin kernel              |
| VS Code support | Kotlin + Java + Python extensions    |
| Extras          | Claude Code CLI, XFCE desktop        |
| Sample          | `src/Fibonacci.kt`                   |

Override versions with the `KOTLIN_VERSION`, `JDK_VERSION`, and `PYTHON_VERSION` build args.
