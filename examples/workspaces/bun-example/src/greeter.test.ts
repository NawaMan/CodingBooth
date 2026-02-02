import { expect, test } from "bun:test";
import { greet } from "./greeter";

test("greet returns greeting with name", () => {
  const result = greet("Alice");
  expect(result).toContain("Hello, Alice!");
  expect(result).toContain("The time is");
});

test("greet uses World as default conceptually", () => {
  const result = greet("World");
  expect(result).toContain("Hello, World!");
});
