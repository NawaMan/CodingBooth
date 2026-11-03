# Legacy Languages Example

Six languages from computing's first decades in one booth: Fortran (1957), COBOL (1959),
ALGOL 68, Prolog (1972), Smalltalk (1980) and Pascal (1970). Each one solves the same small task,
printing the primes up to 30, so you can compare them side by side. Setting up these toolchains
by hand is a weekend of chasing packages. Here it is one `booth` away, and no compiler touches
your host.

**Stack:** GCC 16 (gfortran, gcobol, ga68), SWI-Prolog, Pharo 14, Free Pascal

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/legacy-languages-example
booth

# 2. Inside the booth: run every language, or one at a time
just --list
just run                 # all six
just cobol               # just one
```

Expected output of `just run`:

```text
Fortran: 2 3 5 7 11 13 17 19 23 29
COBOL: 2 3 5 7 11 13 17 19 23 29
ALGOL 68: 2 3 5 7 11 13 17 19 23 29
Prolog: 2 3 5 7 11 13 17 19 23 29
Smalltalk: 2 3 5 7 11 13 17 19 23 29
Pascal: 2 3 5 7 11 13 17 19 23 29
```

## What's included

| Language  | Toolchain                        | Selected as            | Source              |
|-----------|----------------------------------|------------------------|---------------------|
| Fortran   | `gfortran` (GCC)                 | `gcc+fortran`          | `src/primes.f90`    |
| COBOL     | `gcobol` (GCC 15+)               | `gcc+cobol`            | `src/primes.cob`    |
| ALGOL 68  | `ga68` (GCC 16)                  | `gcc+algol68`          | `src/primes.a68`    |
| Prolog    | SWI-Prolog `swipl`               | `prolog`               | `src/primes.pl`     |
| Smalltalk | Pharo VM + image (`pharo`)       | `smalltalk`            | `src/primes.st`     |
| Pascal    | Free Pascal `fpc`                | `fpc`                  | `src/primes.pas`    |

`./run-primes.sh <language>` does the work; build output lands in `build/`.

- The three GCC front ends follow the `GCC_VERSION` build arg in `.booth/Boothfile`, pinned to 16
  here. gcobol and ga68 exist from GCC 15 onward, but GCC 15's ga68 is an early cut that cannot
  compile `whole`, so the ALGOL 68 program needs 16.
- `PROLOG_IMPL=gnu` (or `both`) adds GNU Prolog and its `gplc` native compiler.
- Pharo runs headless here (`pharo eval …`, `pharo st --quit file.st`). On a desktop variant,
  `pharo-ui` opens the Pharo IDE. Pharo is x86_64 only: there is no current Linux arm64 Pharo VM.
- On an IDE variant (`--variant codeserver`), the Fortran, COBOL and Pascal VS Code extensions
  install automatically.
