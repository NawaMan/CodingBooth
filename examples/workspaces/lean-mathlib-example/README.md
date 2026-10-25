# Lean Mathlib Example (experimental)

[Mathlib](https://leanprover-community.github.io/mathlib4_docs/) is Lean's library of
mathematics, and most real Lean work depends on it. This example is a small Mathlib project with
three classic results:

| File | Proves | Shows |
|------|--------|-------|
| `MathlibExample/Primes.lean` | there are infinitely many primes | Euclid's proof, step by step, with Mathlib's lemmas about factorials and divisibility |
| `MathlibExample/Sqrt2.lean` | √2 is irrational, so no fraction squares to 2 | using a general Mathlib theorem, then working with real numbers and fractions |
| `MathlibExample/Inequalities.lean` | 2ab ≤ a² + b², a cube expansion, the triangle inequality | Mathlib's automation: `nlinarith`, `positivity`, `ring` |

Setting Mathlib up is usually the hard part on a laptop. You need the right Lean version for the
Mathlib version, and its prebuilt files (about 0.5 GB to download, about 7 GB unpacked), because
building Mathlib yourself takes hours. Here the booth pins both and shares the download across
projects.

> **Experimental.** The `lean` template is new and not battle-tested yet.

**Stack:** Lean 4.35.0, Mathlib v4.35.0, code-server with the Lean 4 extension,
`lean+mathlib-cache`

## Quick start

```bash
# 1. Start the booth (code-server opens in your browser)
cd examples/workspaces/lean-mathlib-example
booth                 # asks once to allow the ~/.cache/mathlib mount; say yes

# 2. In the booth's terminal, the first time only
just cache            # download Mathlib's prebuilt files (a few minutes the first time)
just build            # check every proof (seconds)
```

Then open `MathlibExample/Primes.lean` and open the infoview (Ctrl+Shift+Enter). Click on the
lines of the proof to see the goal change. The first file you open takes a few seconds, because
Lean loads Mathlib.

`just cache` downloads into your host's `~/.cache/mathlib` and unpacks into this folder's
`.lake/`. With `+mathlib-cache`, a second Mathlib project with the same Mathlib version
downloads nothing: it unpacks in seconds.

## Finding your way around Mathlib

Mathlib has more than 200,000 theorems. You don't need to know their names; you need these:

| To | Do |
|----|----|
| See how a lemma is proved | Put the cursor on its name and press **F12** |
| See a lemma's statement | Hover over it, or write `#check Nat.minFac_prime` on its own line |
| Ask Lean to find the lemma for you | Write `exact?` as the proof. Lean searches Mathlib and suggests a line to click |
| Ask for a lemma that fits the goal | `apply?`, the same idea, for a step instead of the whole proof |
| Let automation try | `simp`, `norm_num` (numbers), `ring` (algebra), `linarith` / `nlinarith` (inequalities), `positivity`, `omega` (whole numbers) |
| Search online | [Loogle](https://loogle.lean-lang.org) (by shape) and [the docs](https://leanprover-community.github.io/mathlib4_docs/) |

Try it: add this at the end of `Primes.lean`, before `end MathlibExample`:

```lean
example (p : ℕ) (hp : p.Prime) : 2 ≤ p := by
  exact?
```

The infoview says `Try this: exact Prime.two_le hp`. Click it to replace `exact?`. When
`exact?` finds nothing (the proof needs more than one lemma), try `apply?` for a first step.

## Start your own Mathlib project

```bash
booth config --no-tui --variant codeserver --select 'lean+vscode-ext+mathlib-cache'
booth
# in the booth
lake new my_math math     # a new project that requires Mathlib
cd my_math
lake exe cache get
lake build
```

`lake new … math` writes the Mathlib version's toolchain into `lean-toolchain`. Run `booth config`
again afterwards, and `lean+toolchain-file` bakes that toolchain into the image.

## How the booth sets it up

`--select 'lean:4.35.0+vscode-ext+mathlib-cache'` on the codeserver variant:

| Piece | What it does |
|-------|--------------|
| `lean` | elan, with Lean pinned to 4.35.0 to match `lean-toolchain` |
| `lean+toolchain-file` | bakes that toolchain into the image (selected automatically) |
| `lean+vscode-ext` | the Lean 4 extension and its infoview |
| `lean+mathlib-cache` | mounts your host's `~/.cache/mathlib`, so downloads are shared; booth asks before starting, because the mount is writable |

`lakefile.toml` pins Mathlib to the tag that matches the toolchain (`rev = "v4.35.0"`), and
`lake-manifest.json` locks every dependency to an exact commit.

The files use Lean's module system (`module`, `public import Mathlib`), as current Mathlib
expects. Without it, every file builds with a warning.

## Tests

The tests download the cache, build, check that no part of Mathlib was compiled, and check that
Lean rejects a false statement. A default run of all examples skips this one, because the first
run unpacks about 7 GB. Run it explicitly:

```bash
examples/workspaces/run-example-tests.sh --example lean-mathlib-example
```
