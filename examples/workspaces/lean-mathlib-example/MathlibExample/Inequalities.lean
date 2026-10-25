module

public import Mathlib

@[expose] public section

/-!
# Inequalities over the real numbers

Where Mathlib's automation shines: `nlinarith`, `positivity`, `ring` and `linarith` close
goals that would take a page by hand. Each proof is one or two lines.
-/

namespace MathlibExample

/-- AM–GM for two numbers: the product is at most the mean of the squares. -/
theorem two_mul_le_sq_add_sq (a b : ℝ) : 2 * a * b ≤ a ^ 2 + b ^ 2 := by
  -- (a - b)² ≥ 0 is the whole idea; nlinarith finds the algebra.
  nlinarith [sq_nonneg (a - b)]

/-- A square plus one is positive, found by `positivity`. -/
example (x : ℝ) : 0 < x ^ 2 + 1 := by positivity

/-- Expanding a cube, found by `ring`. -/
example (a b : ℝ) : (a + b) ^ 3 = a ^ 3 + 3 * a ^ 2 * b + 3 * a * b ^ 2 + b ^ 3 := by ring

/-- The triangle inequality, as a chain of steps. -/
theorem abs_sub_le' (a b c : ℝ) : |a - c| ≤ |a - b| + |b - c| :=
  calc |a - c| = |(a - b) + (b - c)| := by ring_nf
    _ ≤ |a - b| + |b - c| := abs_add_le _ _

end MathlibExample
