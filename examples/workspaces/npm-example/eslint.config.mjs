// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// ESLint flat config with no plugins: the global eslint can resolve nothing
// else, and it cannot parse TypeScript without one — hence banner.mjs.
export default [
  {
    files: ["**/*.mjs"],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: "module",
      globals: { Buffer: "readonly", console: "readonly", process: "readonly" },
    },
    rules: {
      "no-undef": "error",
      "no-unused-vars": "error",
      "prefer-const": "error",
      eqeqeq: "error",
    },
  },
];
