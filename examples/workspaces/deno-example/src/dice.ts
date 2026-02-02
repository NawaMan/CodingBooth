/**
 * Dice Roller - A simple CLI for rolling dice
 * Usage: deno run dice.ts 2d6
 */

export function parseDiceNotation(notation: string): { count: number; sides: number } | null {
  const match = notation.toLowerCase().match(/^(\d+)d(\d+)$/);
  if (!match) return null;
  return {
    count: parseInt(match[1], 10),
    sides: parseInt(match[2], 10),
  };
}

export function rollDice(count: number, sides: number): number[] {
  const rolls: number[] = [];
  for (let i = 0; i < count; i++) {
    rolls.push(Math.floor(Math.random() * sides) + 1);
  }
  return rolls;
}

export function formatResult(notation: string, rolls: number[]): string {
  const total = rolls.reduce((a, b) => a + b, 0);
  const rollsStr = rolls.join(", ");
  return `🎲 Rolling ${notation}: [${rollsStr}] = ${total}`;
}

function main() {
  const args = Deno.args;

  if (args.length === 0) {
    console.log("🎲 Dice Roller - Roll dice using standard notation");
    console.log("");
    console.log("Usage: dice.ts <dice notation>");
    console.log("");
    console.log("Examples:");
    console.log("  dice.ts 2d6    Roll two 6-sided dice");
    console.log("  dice.ts 1d20   Roll one 20-sided die");
    console.log("  dice.ts 4d8    Roll four 8-sided dice");
    Deno.exit(1);
  }

  const notation = args[0];
  const parsed = parseDiceNotation(notation);

  if (!parsed) {
    console.error(`Invalid dice notation: ${notation}`);
    console.error("Use format like: 2d6, 1d20, 3d8");
    Deno.exit(1);
  }

  const rolls = rollDice(parsed.count, parsed.sides);
  console.log(formatResult(notation, rolls));
}

// Run if executed directly
if (import.meta.main) {
  main();
}
