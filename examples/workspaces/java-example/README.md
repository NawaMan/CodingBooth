# Java Example

This example is a batteries-included JVM workspace built around JDK 25. The bundled `Person.java` uses Lombok's `@Value` to define an immutable person type and prints a formatted greeting for a sample person ("Hello, Peter Parker (18)!"), with matching notebooks running the same code interactively. This is the batteries-included JVM story at its fullest: JDK 25, Maven, the JJava notebook kernel, and full IDEs (Eclipse/IntelliJ) all come up together in a single launch. Setting up any one of those by hand is a chore; getting all of them to agree on the same JDK is the kind of afternoon nobody wants. Here you skip it entirely — build with Maven, prototype in a notebook, or open a real IDE, all against one consistent Java 25, from the moment the booth starts.

**Stack:** JDK 25 (Temurin), Jupyter Notebook, JJava kernel

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/java-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Java kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | JDK 25 (Temurin)                     |
| Notebook           | Jupyter with JJava kernel            |
| VS Code extensions | Java language support                |
| IntelliJ plugins   | Lombok (`idea+lombok`)               |
| IntelliJ SDK       | `temurin-25`, registered by `jetbrains-jdk` |

> IntelliJ IDEA Community no longer bundles the Lombok plugin, so without it the IDE flags every
> getter `@Value` generates as unresolved — in a project that compiles fine from Maven. It comes
> from `setup lombok-idea`, the counterpart to `setup lombok-eclipse`. `jetbrains-plugin-pkg` is
> selected too but left empty: it is the escape hatch for any other plugin you want baked in.
