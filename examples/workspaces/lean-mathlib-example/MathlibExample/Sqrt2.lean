module

public import Mathlib

@[expose] public section

/-!
# √2 is irrational

The classic argument: if `p² = 2q²`, then `p` is even, so `q` is even too, and the fraction
was never in lowest terms. Mathlib already has the general fact (the square root of a prime
is irrational), so the proof here is one step. The point is how much a library gives you.
-/

namespace MathlibExample

/-- `√2` is not a ratio of two integers. -/
theorem sqrt_two_irrational : Irrational (Real.sqrt 2) :=
  Nat.prime_two.irrational_sqrt

/-- So no fraction squares to 2. -/
theorem no_rational_sq_eq_two (q : ℚ) : q ^ 2 ≠ 2 := by
  intro h
  -- If q² = 2, then |q| is a rational number equal to √2, which cannot be.
  apply sqrt_two_irrational
  refine ⟨|q|, ?_⟩
  -- Goal: (|q| : ℝ) = √2. Write |q| as √(q²), then use q² = 2.
  rw [Rat.cast_abs, ← Real.sqrt_sq_eq_abs]
  congr 1
  exact_mod_cast h

end MathlibExample
