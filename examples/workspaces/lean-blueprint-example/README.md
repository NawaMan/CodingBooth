# Lean Blueprint Example (experimental)

A **blueprint** is a LaTeX document that plans a formalization. You write the mathematics as you
would on paper, and tag each definition, lemma and theorem with the [Lean 4](https://lean-lang.org)
name that formalizes it. [leanblueprint](https://github.com/PatrickMassot/leanblueprint) builds it
two ways: a PDF, and a web page with a **dependency graph** that colours each result by its state.
Large projects, such as the formalization of Fermat's Last Theorem, use blueprints to split the
work between many people and see what is left.

This example is a two-chapter blueprint:

1. **Odd numbers add up to squares.** 1 + 3 + … + (2n − 1) = n², as a definition, a lemma, a
   theorem and a corollary. All of it is formalized and proved.
2. **Sums of cubes.** Gauss's formula, proved, and **Nicomachus's theorem**
   (0³ + 1³ + … + n³ = (0 + 1 + … + n)²), stated in Lean but **not proved**: its proof is `sorry`.
   The graph shows it as "ready to prove". Replacing that `sorry` is the exercise.

> **Experimental.** The `lean` template and its `blueprint` extension are new and not
> battle-tested yet.

**Stack:** Lean 4.35.0, leanblueprint 0.0.20 (plasTeX + graphviz), TeX Live + XeLaTeX,
code-server with the Lean 4 and LaTeX Workshop extensions

## Quick start

```bash
# 1. Start the booth (code-server opens in your browser)
cd examples/workspaces/lean-blueprint-example
booth

# 2. In the booth, or from the host
just --list
just blueprint     # lake build, then the web version, the PDF, and checkdecls
just serve         # serve blueprint/web on :8000
```

Port 8000 is published as `+8000:8000`: the host port is the **booth port + 8000**. A booth on
port 10000 serves the blueprint at http://localhost:18000; `booth--expose list` in the booth
shows the mapping. Open **Dependency graph** at the top of the page.

`blueprint/print/print.pdf` is the PDF. It opens in code-server.

## Reading the graph

| Node | Means |
|------|-------|
| box | a definition |
| ellipse | a lemma, theorem or corollary |
| green border | the statement is formalized in Lean (`\leanok` on the statement) |
| light green fill, box | a definition that is formalized |
| green fill | the proof is formalized |
| dark green fill | the proof, and the proofs of everything it uses, are formalized |
| light blue fill | the proof is ready to formalize: everything it uses is done |

In this example every node has a green border. Every result in chapter 1 and Gauss's formula is
dark green, and Nicomachus is light blue. The graph page has the full legend.

An arrow means "is used by". A dashed arrow means it is used in the statement, and a solid arrow
means it is used in the proof. Arrows that follow from other arrows are not drawn.

## How the blueprint links to Lean

`blueprint/src/content.tex` holds the mathematics. Three macros connect it to Lean:

| Macro | Meaning |
|-------|---------|
| `\lean{OddSquares.oddSum_eq_sq}` | the Lean declaration that formalizes this statement |
| `\leanok` | in a statement: it is formalized; in a proof: the proof is done |
| `\uses{def:oddSum}` | what it depends on: the arrows of the graph |

`just checkdecls` checks that every `\lean{…}` name really exists in the Lean project. A typo in a
name, or a theorem that was renamed, fails it. The tests check both sides: all 8 names pass, and
a name that does not exist (`OddSquares.noSuchTheorem`) is rejected.

**Prove Nicomachus.** Replace the `sorry` in `OddSquares/Cubes.lean`, add `\leanok` to the proof
in `content.tex`, and run `just blueprint`. The node turns dark green.

## The `leanblueprint` command

In your own project, the `leanblueprint` command does all of this: `leanblueprint new` creates
`blueprint/`, and `leanblueprint all` builds it and runs the check. The command needs the project
to be a git repository. This example is a folder inside the CodingBooth repository, so its `just`
recipes run the two tools that `leanblueprint` runs, `plastex` and `latexmk`, directly. The tests
also run `leanblueprint all` on a copy of this folder that is its own git repository.

`blueprint/src/` was created from leanblueprint's own templates, with the answers
`leanblueprint new` uses by default. Only `content.tex` was written for this example.

## Layout

```
OddSquares/Odd.lean        chapter 1: oddSum and its square, all proved
OddSquares/Cubes.lean      chapter 2: Gauss proved, Nicomachus left as sorry
blueprint/src/content.tex  the blueprint text, with \lean, \leanok, \uses
blueprint/src/web.tex      preamble of the web version (plasTeX)
blueprint/src/print.tex    preamble of the PDF version (XeLaTeX)
blueprint/src/macros/      macros shared by both, and the ones only one of them uses
lakefile.toml              the library, plus the checkdecls dependency
```

Builds go to `blueprint/web/`, `blueprint/print/` and `blueprint/lean_decls`, and are not
committed.
