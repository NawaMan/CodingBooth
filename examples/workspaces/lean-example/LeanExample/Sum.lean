/-!
# Gauss's sum

`sumTo n` adds `0 + 1 + … + n` the slow way, one number at a time. The theorem
below proves it always equals the closed form `n * (n + 1) / 2` — for every `n`,
not just the ones a test happens to try.
-/

namespace LeanExample

/-- `0 + 1 + … + n`, by plain recursion. -/
def sumTo : Nat → Nat
  | 0     => 0
  | n + 1 => sumTo n + (n + 1)

/-- Twice the sum is `n * (n + 1)`, proved by induction on `n`. -/
theorem two_mul_sumTo (n : Nat) : 2 * sumTo n = n * (n + 1) := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [sumTo, Nat.mul_add, ih]
    grind

/-- The closed form itself. -/
theorem sumTo_eq (n : Nat) : sumTo n = n * (n + 1) / 2 := by
  have := two_mul_sumTo n
  omega

end LeanExample
