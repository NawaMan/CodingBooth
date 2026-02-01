import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { parseDiceNotation, rollDice, formatResult } from "./dice.ts";

Deno.test("parseDiceNotation parses valid notation", () => {
  const result = parseDiceNotation("2d6");
  assertEquals(result, { count: 2, sides: 6 });
});

Deno.test("parseDiceNotation handles uppercase", () => {
  const result = parseDiceNotation("1D20");
  assertEquals(result, { count: 1, sides: 20 });
});

Deno.test("parseDiceNotation returns null for invalid input", () => {
  assertEquals(parseDiceNotation("invalid"), null);
  assertEquals(parseDiceNotation("d6"), null);
  assertEquals(parseDiceNotation("2d"), null);
});

Deno.test("rollDice returns correct number of rolls", () => {
  const rolls = rollDice(3, 6);
  assertEquals(rolls.length, 3);
});

Deno.test("rollDice values are within range", () => {
  const rolls = rollDice(100, 6);
  for (const roll of rolls) {
    assertEquals(roll >= 1 && roll <= 6, true);
  }
});

Deno.test("formatResult includes total", () => {
  const result = formatResult("2d6", [3, 4]);
  assertEquals(result.includes("= 7"), true);
});
