# Lean exercises

This is a Lean 4 project (core library only, no Mathlib). The `sorry`s in `Exercises/` are proofs
to write.

## How to work

- Use the **lean-lsp** MCP tools to see what Lean sees, instead of guessing:
  - `lean_goal` at a line inside a proof shows the goal there: what is known, and after `⊢`, what
    is left. Check it before and after each step.
  - `lean_diagnostic_messages` on a file lists its errors and warnings.
  - `lean_hover_info` shows the type of a name; `lean_local_search` finds lemmas by name.
- Replace one `sorry` at a time, then check that file's diagnostics before moving on.
- Do not change a theorem's statement, and do not add `axiom`s. A proof that changes the claim
  proves nothing.
- Helper lemmas are fine; put them just above the theorem that uses them.
- Finish with `lake build`. Done means it succeeds and prints no `declaration uses 'sorry'`.

Useful tactics in core Lean: `induction n with ...`, `simp [defs, *]`, `omega` (linear
arithmetic over Nat/Int), `grind` (also handles ring equations), `rfl`, `decide`.
