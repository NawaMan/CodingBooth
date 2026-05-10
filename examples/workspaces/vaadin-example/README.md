# Vaadin Example

A minimal [Vaadin Flow](https://vaadin.com/flow) app — write the UI in pure Java, Vaadin handles the browser side — running inside a CodingBooth workspace.

## Run

```bash
./booth run
# inside the booth:
mvn spring-boot:run
```

The first run downloads dependencies (incl. the Vaadin frontend toolchain — Node.js is preinstalled in the booth so this is fast). When it's ready, open http://localhost:8080/ on the host. Click the button — Vaadin updates the page through its WebSocket bridge with zero handwritten JavaScript.

## What's inside

- `.booth/Boothfile` — JDK (Temurin 21), Maven, Node.js (Vaadin uses it during the frontend build), and the Java VS Code extension.
- `.booth/config.toml` — exposes container port 8080.
- `pom.xml` — `spring-boot-starter-parent` 3.4 + `vaadin-spring-boot-starter` 24.5.
- `src/main/java/com/example/Application.java` — Spring Boot entry + a `MainView` (`@Route("")`) with a counter button.
