# All Java Example

This example is a comprehensive Java development environment bundling multiple JDK versions and build tools. It installs JDKs 8, 9, 17, 21, 23, 24, and 25 switchable via jEnv, plus Maven, Gradle, and jbang, and a Lombok-based sample project you can build and test on any of them. Try / compare side-by-side: seven JDKs live in one container so you can build and test the same code across Java versions. Switch from JDK 8 to 25 with a single `jenv local` and re-run — perfect for verifying a library works on every version you support, or reproducing a bug that only shows up on one. No juggling SDKMAN installs or separate machines: every JDK, plus Maven, Gradle, and jbang, is right there for instant version-by-version comparison.

**Stack:** JDK 8/9/17-25, jEnv, Maven, Gradle, jbang, Eclipse, IntelliJ IDEA, Lombok

## Quick start

```bash
# 1. Launch the booth
cd examples/all-java-example
../../codingbooth

# 2. Inside the booth — switch Java versions with jEnv
jenv versions                    # list available JDKs
jenv local 21                    # switch to JDK 21
java -version                    # verify

# 3. Build the Maven project
mvn compile

# 4. Try Jupyter notebooks
#    Open Demo-Java.ipynb in VS Code or JupyterLab

# 5. Run a one-liner with jbang
jbang -c 'System.out.println("Hello from jbang!")'
```

## What's included

| Tool / Feature        | Details                                |
|-----------------------|----------------------------------------|
| JDK versions          | 8, 9, 17, 21, 23, 24, 25 via jEnv     |
| Build tools           | Maven, Gradle                          |
| Scripting             | jbang                                  |
| Notebooks             | IJava Jupyter kernel (per JDK version) |
| IDEs (desktop)        | Eclipse, IntelliJ IDEA                 |
| VS Code extensions    | Java language support, Lombok          |
