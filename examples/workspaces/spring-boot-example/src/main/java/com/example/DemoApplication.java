package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
public class DemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}

@RestController
class GreetingController {

    @GetMapping("/")
    public String index() {
        return "Hello from Spring Boot in CodingBooth! Try /api/ping";
    }

    @GetMapping("/api/ping")
    public java.util.Map<String, String> ping() {
        return java.util.Map.of("status", "ok", "message", "pong");
    }
}
