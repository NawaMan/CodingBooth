# Vetting report: https://github.com/jonschlinkert/is-odd

Commit `a80ee0d831a8ee69f1fad5b4673491847975eb26`, vetted 2026-10-18.

## What it is

Tiny MIT-licensed npm library `is-odd` (v3.0.1) that returns whether a value is an odd integer within `Number.MAX_SAFE_INTEGER`. Runtime code is `index.js` plus a Mocha test file; it `require`s `is-number` and does arithmetic/`TypeError` checks only.

## How to build and run it

Install as a dependency (`README.md:13`):

```sh
npm install --save is-odd
```

Install deps and run tests (`README.md:43`):

```sh
npm install && npm test
```

`package.json:27-29` maps `test` to `mocha`. Optional readme regen (`README.md:55`):

```sh
npm install -g verbose/verb#dev verb-generate-readme && verb
```

No compile step.

## What runs automatically

- `package.json:27-29`: only `test` (`mocha`). No `preinstall`/`install`/`postinstall` or other lifecycle scripts.
- `.travis.yml:1-12`: Travis CI on linux/osx, Node `node` and 4–10. Default Node job installs deps and runs `npm test`; nothing local.
- `.npmrc:1`: `package-lock=false` only.
- No Makefile, `setup.py`, `build.rs`, or committed git hooks.

## Network and secrets

No outbound I/O or credential reads in executable code (`index.js:10-23`, `test.js:1-32`).

Docs/metadata URLs only: npm/Travis badges and GitHub/npm links (`README.md:1`, `package.json:5-15`), plus author/contributor pages. `npm install` fetches `is-number@^6.0.0` (`package.json:31-33`) from the npm registry. Optional `verb` install hits GitHub (`README.md:55`). Travis would talk to Travis/GitHub/npm on CI only.

No `process.env`, `~/.ssh`, `~/.aws`, browser profiles, wallets, or other secret paths.

## Red flags

None found. Source is short, readable JS (`index.js:12-23`). No obfuscation, `eval`, pipe-to-shell, or bundled binaries.

## Verdict

LOOKS FINE. Matches the claimed odd-integer helper; no install hooks, no network/secret use in code, no hidden payloads. `npm install` still pulls third-party `is-number` from npm, which is outside this tree.
