// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Draw a box around whatever comes in on stdin: `ts-node hello.ts | node banner.mjs`.
// Plain JavaScript on purpose — eslint lints it without any plugin.

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}

const lines = Buffer.concat(chunks).toString("utf8").trimEnd().split("\n");
const width = Math.max(...lines.map((line) => line.length));

console.log(`┌${"─".repeat(width + 2)}┐`);
for (const line of lines) {
  console.log(`│ ${line.padEnd(width)} │`);
}
console.log(`└${"─".repeat(width + 2)}┘`);
