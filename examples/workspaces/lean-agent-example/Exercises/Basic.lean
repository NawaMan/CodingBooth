/-!
# Exercises: numbers

Each `sorry` is a proof still to write. Ask Claude Code to fill them in (`just prove`),
or try them yourself in Neovim (`nvim Exercises/Basic.lean`) with the infoview open (`\i`).
-/

namespace Exercises

/-- `0 + 1 + … + n`. -/
def sumTo : Nat → Nat
  | 0     => 0
  | n + 1 => sumTo n + (n + 1)

/-- `0³ + 1³ + … + n³`. -/
def cubeSum : Nat → Nat
  | 0     => 0
  | n + 1 => cubeSum n + (n + 1) ^ 3

/-- Warm-up: addition does not care about order. -/
theorem add_comm' (a b : Nat) : a + b = b + a := by
  sorry

/-- Gauss: twice the sum of `0 … n` is `n * (n + 1)`. -/
theorem two_mul_sumTo (n : Nat) : 2 * sumTo n = n * (n + 1) := by
  sorry

/-- Nicomachus: the sum of the first cubes is the square of the sum. -/
theorem cubeSum_eq_sq (n : Nat) : cubeSum n = sumTo n ^ 2 := by
  sorry

end Exercises
