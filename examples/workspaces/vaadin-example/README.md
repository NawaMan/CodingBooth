# Vaadin Example

This example is a minimal Vaadin Flow app where the entire UI is written in pure Java and Vaadin drives the browser side, running inside a CodingBooth workspace. The demo renders a heading and a button that, on each click, pushes a "Clicked N times" notification to the page over Vaadin's server bridge with zero handwritten JavaScript. It showcases how much fiddly setup the booth absorbs: Vaadin quietly needs a full JDK, Maven, and a Node.js frontend toolchain, and lining all three up by hand is exactly the kind of yak-shave that stops people from ever trying the framework. Here they arrive pre-provisioned and pre-agreed, so you go from zero to a live server-driven UI without touching npm, nvm, or a JDK installer.

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
