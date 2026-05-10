# Spring Boot Example

A minimal [Spring Boot](https://spring.io/projects/spring-boot) web app running inside a CodingBooth workspace.

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
