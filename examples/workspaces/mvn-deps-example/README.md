# Maven Deps Example

Demonstrates pre-downloading Maven dependencies at booth-build time so the first run inside the booth is offline-fast.

**Stack:** JDK 21, Maven

## Quick start

```bash
# 1. Launch the booth (dependencies are resolved during the image build)
cd examples/workspaces/mvn-deps-example
booth

# 2. Inside the booth — compile and run; no network round-trips for deps
mvn compile -q exec:java -Dexec.mainClass=com.example.App
```

## What's included

| Component | Details                                                            |
|-----------|--------------------------------------------------------------------|
| JDK       | Temurin 21                                                         |
| Build     | Maven (warmed cache at `/opt/mvn-cache` populated from `pom.xml`)   |
| Sample    | `src/main/java/com/example/App.java`                               |

The `.booth/Boothfile` mounts the project's `pom.xml` during build and runs `mvn dependency:resolve`, so the local `~/.m2` cache is pre-populated inside the image.
