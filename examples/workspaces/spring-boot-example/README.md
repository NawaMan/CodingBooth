# Spring Boot Example

This example is a minimal Spring Boot web app running inside a CodingBooth workspace. A single `@RestController` serves a plain-text greeting at `/` and a JSON `pong` map at `/api/ping`. It showcases precise version compatibility: a matched Temurin 21 JDK and Maven are pinned together, and Java builds are unforgiving when a toolchain drifts. The booth guarantees the two agree, so you never hit the classic "unsupported class file version" wall or a wrong-JDK build failure — the exact toolchain the project expects is simply present.

## Run

```bash
./booth run
# inside the booth:
mvn spring-boot:run
```

Then open:
- http://localhost:8080/ — text greeting
- http://localhost:8080/api/ping — JSON

The first run downloads dependencies; subsequent runs are fast.

## What's inside

- `.booth/Boothfile` — sets up the JDK (Temurin 21), Maven, and Java VS Code extension.
- `.booth/config.toml` — exposes container port 8080 to the host.
- `pom.xml` — Spring Boot 3.4 parent + `spring-boot-starter-web`.
- `src/main/java/com/example/DemoApplication.java` — entry point + `@RestController` with two routes.
