# OCaml Example

> **Experimental.** The `ocaml` setup is new and marked `[experimental]` in `booth config`; expect rough edges.

This example is an OCaml workspace with Dune, UTop and OCamlFormat. The bundled `calc` command parses an integer expression (`+ - * /`, unary minus, parentheses), prints it back fully parenthesized so you can see how it was parsed, and evaluates it. It is small but shows what OCaml is good at: the syntax tree is one variant type, the parser is a few mutually recursive functions, and errors — a stray character, a missing `)`, division by zero — are `result` values the compiler makes you handle, not exceptions.

The toolchain is the part worth having done for you. Building the OCaml compiler plus Dune, UTop and OCamlFormat through opam compiles everything from source; it takes a long time and once ran a build host out of memory. Here the `ocaml` setup unpacks a prebuilt bundle from CodingBoothPrebuilt instead — compiler, tools and a ready opam switch named `booth` — so the first `booth` is a download, not a compile. The tests use plain assertions and need no extra opam packages; anything you `opam install` yourself may still compile from source.

**Stack:** OCaml 5.4.1, Dune, UTop, OCamlFormat, opam

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/ocaml-example
booth

# 2. Inside the booth
just --list
just run "(1 + 2) * 3"     # ((1 + 2) * 3) = 9
just test
just repl                  # UTop with the calc library loaded: Calc.calculate "6 * 7";;
```

Every recipe also works from the host; it runs in this project's booth, starting one if needed.

## What's included

| Component  | Details                                                       |
|------------|---------------------------------------------------------------|
| Language   | OCaml 5.4.1 (prebuilt), opam switch `booth`                   |
| Build      | Dune 3.24 — `src/` library, `bin/` CLI, `test/` tests         |
| REPL       | UTop 2.17 (`just repl`)                                       |
| Formatter  | OCamlFormat 0.29 (`just fmt`, pinned in `.ocamlformat`)       |

## Commands

| Recipe          | What it does                                             |
|-----------------|----------------------------------------------------------|
| `just build`    | `dune build`                                             |
| `just test`     | `dune test` — the assertions in `test/test_calc.ml`      |
| `just run EXPR` | Parse, print and evaluate `EXPR`                         |
| `just fmt`      | Reformat with OCamlFormat, then check nothing is left    |
| `just repl`     | `dune utop src`                                          |
| `just shell`    | Open a shell in the booth                                |
