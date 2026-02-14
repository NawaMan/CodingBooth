# All Java Example

Comprehensive Java development environment with multiple JDK versions and build tools.

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
