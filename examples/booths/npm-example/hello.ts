// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// A typed greeting for ts-node to run and tsc to check. No imports: the tools
// are installed globally, so this file only uses the language itself.
// (@types/node is not installed, so the one Node global it needs is declared.)
declare const process: { argv: string[] };

type Tool = { name: string; usedBy: string };

const TOOLS: readonly Tool[] = [
  { name: "typescript", usedBy: "just check (tsc --noEmit)" },
  { name: "ts-node", usedBy: "just run (this file)" },
  { name: "eslint", usedBy: "just lint (banner.mjs)" },
  { name: "prettier", usedBy: "just lint (every sample)" },
  { name: "figlet-cli", usedBy: "just run (the banner)" },
  { name: "cowsay", usedBy: "just run (the cow)" },
];

export function greeting(name: string): string[] {
  const width = Math.max(...TOOLS.map((tool) => tool.name.length));
  return [
    `Hello, ${name}! These npm globals came with the booth:`,
    "",
    ...TOOLS.map((tool) => `${tool.name.padEnd(width)}  ${tool.usedBy}`),
  ];
}

console.log(greeting(process.argv[2] ?? "world").join("\n"));
