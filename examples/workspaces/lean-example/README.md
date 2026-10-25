# Lean Example (experimental)

This example is a small [Lean 4](https://lean-lang.org) project. Lean is a programming language and a
theorem prover, so the same file holds a program and a proof that the program is right. There are
two samples. `LeanExample/Sum.lean` adds `0 + 1 + … + n` one number at a time and proves the sum
always equals `n * (n + 1) / 2`. `LeanExample/Fib.lean` has the slow textbook Fibonacci and a fast
one built on a loop, plus a proof that both give the same answer for every input. `Main.lean` runs
the fast version, and the proof is what lets you trust its output. Lean needs one thing pinned:
the toolchain named in `lean-toolchain`. That pin is baked into the image, so the first build does
not download it.

> **Experimental.** The `lean` template is new and not battle-tested yet. This example uses only
> Lean's core library. It does not use Mathlib (see [Mathlib](#mathlib) below).

**Stack:** Lean 4.35.0 (elan + lake), code-server with the `leanprover.lean4` extension

## Quick start

```bash
# 1. Start the booth (code-server opens in your browser)
cd examples/workspaces/lean-example
booth

# 2. Inside the booth
just --list
just build                           # lake build: checks every proof, builds the program
just run 30                          # sumTo 30 = 465 = 30 * 31 / 2,  fastFib 30 = 832040
just check LeanExample/Fib.lean      # check one file
```

Open `LeanExample/Fib.lean` in code-server and put the cursor inside a proof. The **Lean
Infoview** panel shows the goal at that point: what is known and what is still to prove. That
panel is where you write a Lean proof.

Every `just` recipe also works from the host: `just build` starts the booth, runs the build, and
stops the booth again.

## What a proof buys you

Change the theorem in `Sum.lean` to a false statement, for example
`2 * sumTo n = n * n`, and run `just build`. The build fails and Lean shows the exact goal it
could not close. The test suite checks this too: it gives Lean the false statement
`sumTo 4 = 11` and expects Lean to reject it. A tool that accepts every proof would pass the
other tests, so this check is the one that shows Lean is really checking.

A proof that is left as `sorry` still compiles and gives only a warning. The tests fail if
`sorry` appears anywhere in the build.

## What's included

| Component       | Details                                                              |
|-----------------|----------------------------------------------------------------------|
| Toolchain       | elan in `/opt/elan`; Lean 4.35.0 from `lean-toolchain`, baked in by `lean+toolchain-file` |
| Build           | lake (comes with the toolchain); `lakefile.toml`, no dependencies    |
| VS Code support | `leanprover.lean4`: language server, live errors, the infoview       |
| Proof samples   | `LeanExample/Sum.lean` (induction + `grind`), `LeanExample/Fib.lean` (a generalized loop invariant) |

To change the version, edit `lean-toolchain` and keep the template pin the same, so that one
toolchain is installed and not two:
`booth config --no-tui --overwrite --variant codeserver --select 'lean:4.36.0+vscode-ext'`.

## Mathlib

[Mathlib](https://leanprover-community.github.io/mathlib4_docs/) is Lean's large library of
mathematics. Most real math in Lean depends on it. This example leaves it out, because Mathlib is
big. A Mathlib project does not build Mathlib, which takes hours. It downloads Mathlib's prebuilt
files with `lake exe cache get` instead: about 0.5 GB that unpack to about 7 GB in the project's
`.lake/`. To start a Mathlib project in a booth:

```bash
booth config --no-tui --select 'lean+mathlib-cache+vscode-ext' --variant codeserver
booth
# inside the booth
lake new my_math math && cd my_math
lake exe cache get          # downloads Mathlib's prebuilt files
lake build
```

`+mathlib-cache` mounts your host's `~/.cache/mathlib`. With it, each Mathlib version downloads
once for all projects and booths, not once per booth. A second project then unpacks in seconds. The mount is writable, so booth asks for
consent before it starts. Mathlib changes its toolchain often. `lake new … math` writes the
toolchain that Mathlib uses at that time into `lean-toolchain`, and elan installs that toolchain
on first use. Run `booth config` again after that, and `lean+toolchain-file` bakes the new
toolchain into the image.

## Layout

```
LeanExample/Sum.lean     sumTo and its closed form, by induction
LeanExample/Fib.lean     fib (spec), fastFib (impl), and fastFib_eq_fib
LeanExample.lean         the library root, imports both
Main.lean                the executable: lake exe lean_example [n]
lakefile.toml            the package: one library, one executable
lean-toolchain           the pinned toolchain (leanprover/lean4:v4.35.0)
```
