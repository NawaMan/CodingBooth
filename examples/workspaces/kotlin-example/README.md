# Kotlin Example

A Kotlin program that compiles to a runnable JAR, plus Python and a Kotlin notebook kernel for exploration.

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
