"""A tiny proof search: try each tactic on each statement, and keep the first one Lean accepts.

This is the loop at the heart of AI theorem proving, minus the AI: something proposes a proof,
Lean checks it, and only checked proofs count. Swap TACTICS for a model's suggestions and the
rest stays the same.

    python proof_search.py
"""

from pathlib import Path

from lean_interact import Command, LeanREPLConfig, LeanServer

STATEMENTS = [
    "2 + 2 = 4",
    "∀ n : Nat, n + 0 = n",
    "∀ a b : Nat, a + b = b + a",
    "∀ xs : List Nat, xs.reverse.reverse = xs",
    "∀ n : Nat, n < 2 ^ n",
    "2 ^ 10 = 1024",
    "∀ n : Nat, n + 1 ≤ n * n",  # false (n = 0), so nothing may prove it
]

# Cheapest first: rfl and decide compute, the rest search.
TACTICS = ["rfl", "decide", "simp", "omega", "grind", "intro n; induction n <;> simp [Nat.pow_succ] <;> omega"]


def lean_version() -> str:
    """The toolchain this folder pins, e.g. v4.35.0, so the prebuilt REPL is the one used."""
    pin = (Path(__file__).parent / "lean-toolchain").read_text().strip()
    return pin.split(":")[-1]


def search(server: LeanServer, statement: str) -> str | None:
    """The first tactic that proves `statement`, or None."""
    for tactic in TACTICS:
        reply = server.run(Command(cmd=f"theorem t : {statement} := by {tactic}"))
        if reply.lean_code_is_valid(allow_sorry=False):
            return tactic
    return None


def main() -> int:
    server = LeanServer(LeanREPLConfig(lean_version=lean_version()))
    unproved = 0
    for statement in STATEMENTS:
        tactic = search(server, statement)
        if tactic is None:
            unproved += 1
        print(f"{'✓' if tactic else '✗'} {statement:<42} {tactic or 'no tactic worked'}")
    print(f"{len(STATEMENTS) - unproved} of {len(STATEMENTS)} proved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
