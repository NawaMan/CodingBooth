# Java Example

Modern Java development environment with JDK 25 and essential build tools.

**Stack:** JDK 25, Maven, Gradle, jEnv, jbang, Eclipse, IntelliJ IDEA

## Quick start

```bash
# 1. Launch the booth
cd examples/java-example
../../codingbooth

# 2. Inside the booth — build and run the Maven project
mvn compile
mvn exec:java

# 3. Try jbang
jbang -c 'System.out.println("Hello from jbang!")'

# 4. Open Jupyter notebooks
#    Open Demo-Java.ipynb in VS Code — uses the JJava kernel

# 5. Switch JDK versions
jenv versions
jenv local 25
java -version
```

## What's included

| Tool / Feature     | Details                            |
|--------------------|------------------------------------|
| JDK                | 25 (Temurin)                       |
| Build tools        | Maven, Gradle                      |
| Version manager    | jEnv                               |
| Scripting          | jbang                              |
| Notebooks          | JJava Jupyter kernel               |
| IDEs (desktop)     | Eclipse, IntelliJ IDEA with Lombok |
| VS Code extensions | Java language support              |
