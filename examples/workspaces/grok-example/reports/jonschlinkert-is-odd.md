# Vetting report: https://github.com/jonschlinkert/is-odd

Commit `a80ee0d831a8ee69f1fad5b4673491847975eb26`, vetted 2026-10-18.

## What it is

`is-odd` (version 3.0.1) is a small Node.js library that returns true when a value is an odd integer within JavaScript's safe-integer range (`index.js:12-23`, `package.json:2-4`). It accepts numbers or numeric strings, rejects non-integers and values above `Number.MAX_SAFE_INTEGER`, and depends on the npm package `is-number` for the number check (`index.js:10`, `package.json:28-29`).

## How to build and run it

There is no compile step. The README expects:

- Install: `npm install --save is-odd` (`README.md:12`)
- Tests: `npm install && npm test` (`README.md:44`), which runs the `test` script `mocha` (`package.json:25-26`) against `test.js`
- Optional readme regeneration: `npm install -g verbose/verb#dev verb-generate-readme && verb` (`README.md:57`)

Usage is `require('is-odd')` in Node.js `>=4` (`README.md:20`, `package.json:22-24`). The published file set is only `index.js` (`package.json:18-20`).

## What runs automatically

Nothing in this tree runs on install or clone. `package.json` defines a single script, `test` (`package.json:25-26`). There is no `preinstall`, `postinstall`, `prepare`, or other lifecycle script, and no `Makefile`, `setup.py`, or `build.rs`.

`.npmrc:1` sets `package-lock=false`, so npm will not write a lockfile. `.travis.yml:1-14` only selects Linux and macOS and Node versions `node`, `10`, `9`, `8`, `7`, `6`, `5`, and `4`, with `sudo: false` and no custom `script`. There is no `.github` workflow directory. Files under `.git/hooks/` are Git's default `*.sample` scripts. Git does not run them. `pre-commit.sample:8` says to rename the file to enable it.

## Network and secrets

`index.js` and `test.js` do not open sockets, read `process.env`, or touch `~/.ssh`, `~/.aws`, browser data, wallets, or other credentials. The only runtime import is `is-number` (`index.js:10`).

`npm install` fetches that package, plus devDependencies `gulp-format-md` and `mocha`, from the npm registry (`package.json:28-33`). Those package trees are not in this repo. The optional docs command also installs `verbose/verb#dev` from GitHub and `verb-generate-readme` from npm (`README.md:57`).

These hosts appear only as links, badges, or git metadata, and the library does not request them:

- `https://github.com/jonschlinkert/is-odd` (`package.json:5`, `.git/config:7`)
- `https://github.com/jonschlinkert/is-odd/issues` (`package.json:15`)
- `http://brainstorage.me/semigradsky`, `https://dym.sh`, `http://twitter.com/jonschlinkert`, `www.rouvenwessling.de` (`package.json:8-11`)
- `img.shields.io`, `npmjs.com`, `npmjs.org`, `travis-ci.org` (`README.md:1`)
- `linkedin.com`, `github.com`, `twitter.com`, and the related-project npm/GitHub URLs (`README.md:66-85`)

## Red flags

None found.

## Verdict

LOOKS FINE. The checked-in code is the odd-integer check the README describes, with no install hooks, no encoded or fetched execution, no bundled binaries, and no credential access. Running tests still installs `is-number`, `mocha`, and `gulp-format-md` from the npm registry. Those packages are outside this tree. The global `verbose/verb#dev` install is only for regenerating the readme.
