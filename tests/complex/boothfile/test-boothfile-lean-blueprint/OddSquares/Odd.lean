/-!
# Odd numbers add up to squares

Blueprint chapter 1: every node of this chapter is formalized and proved.
-/

namespace OddSquares

/-- `1 + 3 + 5 + …`, the first `n` odd numbers. -/
def oddSum : Nat → Nat
  | 0     => 0
  | n + 1 => oddSum n + (2 * n + 1)

/-- Adding one more odd number. -/
theorem oddSum_succ (n : Nat) : oddSum (n + 1) = oddSum n + (2 * n + 1) := rfl

/-- The sum of the first `n` odd numbers is `n * n`. -/
theorem oddSum_eq_sq (n : Nat) : oddSum n = n * n := by
  induction n with
  | zero => rfl
  | succ k ih =>
    rw [oddSum_succ, ih]
    grind

/-- So it is always a perfect square. -/
theorem oddSum_isSquare (n : Nat) : ∃ m, oddSum n = m * m :=
  ⟨n, oddSum_eq_sq n⟩

end OddSquares
