# Lean Interact Example (experimental)

This example drives [Lean 4](https://lean-lang.org) from Python. It uses
[LeanInteract](https://github.com/augustepoiroux/LeanInteract), a library that sends Lean code to
a Lean REPL and returns the result as Python objects: errors, warnings, and the goal still to
prove at each `sorry`. Python writes the Lean code and decides what to try next. Lean checks it.

This is how notebooks are used with Lean today. You do not write cells in Lean: there is no
maintained Lean kernel for Jupyter. You write Python cells that call Lean. It is also the loop
behind AI theorem proving: something proposes a proof, Lean checks it, and only checked proofs
count.

> **Experimental.** The `lean` template and its `interact` extension are new and not
> battle-tested yet. To write Lean proofs by hand, with the Infoview, use `lean-example`.

**Stack:** JupyterLab (notebook variant), Python 3.12, Lean 4.35.0, LeanInteract 0.11.6

## Quick start

```bash
# 1. Start the booth (JupyterLab opens in your browser)
cd examples/workspaces/lean-interact-example
booth
# then open lean_from_python.ipynb and run the cells

# 2. Or from a terminal, in the booth or on the host
just --list
just search        # try tactics on statements, keep what Lean accepts
just notebook      # run the whole notebook headless and print its output
```

`just search` prints:

```
✓ 2 + 2 = 4                                  rfl
✓ ∀ n : Nat, n + 0 = n                       simp
✓ ∀ a b : Nat, a + b = b + a                 omega
✓ ∀ xs : List Nat, xs.reverse.reverse = xs   simp
✓ ∀ n : Nat, n < 2 ^ n                       intro n; induction n <;> simp [Nat.pow_succ] <;> omega
✓ 2 ^ 10 = 1024                              rfl
✗ ∀ n : Nat, n + 1 ≤ n * n                   no tactic worked
6 of 7 proved
```

The last statement is false (it fails for n = 0), so no tactic may prove it. That ✗ is the
point: Lean does not accept a proof just because something produced one.

## The notebook

`lean_from_python.ipynb` has five short sections:

1. **Check a theorem.** Send it, and read whether Lean accepts it.
2. **A false theorem is rejected.** Lean reports the error, with the goal it could not close.
3. **Build on earlier results.** Each reply has an `env` number. Pass it back, and later code can
   use earlier definitions.
4. **Prove step by step.** Start with `sorry`, then send one tactic at a time with `ProofStep` and
   print the goal after each one. This is the VS Code Infoview, as Python data.
5. **Search for proofs.** The same loop as `just search`.

## How the booth sets it up

`--select 'python:3.12/lean:4.35.0+interact'` on the notebook variant:

| Piece | What it does |
|-------|--------------|
| `lean` | elan in `/opt/elan`, Lean pinned to 4.35.0 to match `lean-toolchain` |
| `lean+interact` | `pip install lean-interact==0.11.6`, and builds the Lean REPL for 4.35.0 when the image is built |
| `/opt/lean-interact/cache` | where the REPL is built; writable, so another Lean version can add its own at run time |

LeanInteract builds a REPL for each Lean version, and that build takes minutes. It happens once
when the image is built, so the first `LeanREPLConfig()` in the notebook starts in seconds. If you
ask for another Lean version, LeanInteract builds a REPL for it on first use. The cache is
writable, so that works, but it is slow the first time.

## Layout

```
lean_from_python.ipynb   the tour: check, reject, reuse, step through, search
proof_search.py          the search loop as a script (`just search`); the notebook imports it
lean-toolchain           the Lean version this folder uses (leanprover/lean4:v4.35.0)
```
