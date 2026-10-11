# Spring Boot Example

This example is a minimal Spring Boot web app running inside a CodingBooth workspace. A single `@RestController` serves a plain-text greeting at `/` and a JSON `pong` map at `/api/ping`. It showcases precise version compatibility: a matched Temurin 21 JDK and Maven are pinned together, and Java builds are unforgiving when a toolchain drifts. The booth guarantees the two agree, so you never hit the classic "unsupported class file version" wall or a wrong-JDK build failure — the exact toolchain the project expects is simply present.

## Run

```bash
./booth run
# inside the booth:
just --list
just run                 # mvn spring-boot:run
```

Then open:
- http://localhost:8080/ — text greeting
- http://localhost:8080/api/ping — JSON

The first run downloads dependencies; subsequent runs are fast.

## Shared Gradle cache

The booth also installs Gradle and mounts `booth-cache-gradle` on `~/.gradle/caches/modules-2`. The Spring app still builds with Maven. `cache-try/` is a one-dependency Gradle build used only to fill that volume. The first start rebuilds the image so Gradle is on `PATH`.

```bash
./booth -- bash -lc 'cd cache-try && gradle dependencies --no-daemon'
```

Copy this folder to a second path and run the same command. The second run does not print `Downloading` for Guava. Run one Gradle booth at a time; two writers on `modules-2` can block each other. List the volume with `docker volume ls --filter label=cb.volume=cache`.

## What's inside

- `.booth/Boothfile` — sets up the JDK (Temurin 21), Maven, Gradle, and the Java VS Code extension.
- `.booth/config.toml` — exposes container port 8080 to the host, and mounts `booth-cache-gradle`.
- `pom.xml` — Spring Boot 3.4 parent + `spring-boot-starter-web`.
- `src/main/java/com/example/DemoApplication.java` — entry point + `@RestController` with two routes.
- `cache-try/` — small Gradle build (`com.google.guava:guava:33.4.8-jre`) for the shared cache.
