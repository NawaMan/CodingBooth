#!/usr/bin/env bun

const COLORS = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  blue: "\x1b[34m",
  yellow: "\x1b[33m",
};

function greet(name: string, useColor: boolean = false): string {
  const time = new Date().toLocaleTimeString();
  const greeting = `Hello, ${name}! The time is ${time}.`;

  if (useColor) {
    return `${COLORS.green}Hello, ${COLORS.blue}${name}${COLORS.reset}! The time is ${COLORS.yellow}${time}${COLORS.reset}.`;
  }
  return greeting;
}

function main() {
  const args = Bun.argv.slice(2);

  if (args.includes("--help") || args.includes("-h")) {
    console.log("👋 Greeter - A friendly greeting CLI");
    console.log("");
    console.log("Usage: greeter.ts [options] [name]");
    console.log("");
    console.log("Options:");
    console.log("  --color    Use colorful output");
    console.log("  --help     Show this help");
    console.log("");
    console.log("Examples:");
    console.log("  greeter.ts              Greet the world");
    console.log("  greeter.ts Alice        Greet Alice");
    console.log("  greeter.ts --color Bob  Greet Bob with colors");
    process.exit(0);
  }

  const useColor = args.includes("--color");
  const name = args.filter(a => !a.startsWith("--"))[0] || "World";

  console.log(greet(name, useColor));
}

// Export for testing
export { greet };

// Run if executed directly
main();
