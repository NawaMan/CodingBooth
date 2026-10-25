/-!
# Sums of cubes

Blueprint chapter 2: the definitions and Gauss's formula are proved; Nicomachus's
theorem is stated but its proof is left as `sorry` -- the blueprint shows it as
"statement formalized, proof to do". Replacing that `sorry` is the exercise.
-/

namespace OddSquares

/-- `0 + 1 + … + n`. -/
def sumTo : Nat → Nat
  | 0     => 0
  | n + 1 => sumTo n + (n + 1)

/-- Gauss: twice the sum is `n * (n + 1)`. -/
theorem two_mul_sumTo (n : Nat) : 2 * sumTo n = n * (n + 1) := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [sumTo, Nat.mul_add, ih]
    grind

/-- `0³ + 1³ + … + n³`. -/
def cubeSum : Nat → Nat
  | 0     => 0
  | n + 1 => cubeSum n + (n + 1) ^ 3

/-- Nicomachus: the sum of the first cubes is the square of the sum. Not proved yet. -/
theorem cubeSum_eq_sq_sumTo (n : Nat) : cubeSum n = sumTo n ^ 2 := by
  sorry

end OddSquares
