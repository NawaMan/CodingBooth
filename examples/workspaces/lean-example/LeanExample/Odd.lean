/-!
# Odd numbers add up to a square

    1             = 1  = 1²
    1 + 3         = 4  = 2²
    1 + 3 + 5     = 9  = 3²
    1 + 3 + 5 + 7 = 16 = 4²

The pattern holds for every `n`. The proof below shows it one step at a time, the way
you would on paper: each line of the `calc` block is one equation, and the part after
`:=` is the reason that step is allowed. Put the cursor on a line in VS Code and the
Lean Infoview shows what is known at that point.
-/

namespace LeanExample

/-- `1 + 3 + 5 + …`, the first `n` odd numbers. The `n`-th one is `2 * n + 1`. -/
def oddSum : Nat → Nat
  | 0     => 0
  | n + 1 => oddSum n + (2 * n + 1)

/-- The sum of the first `n` odd numbers is `n * n`. -/
theorem oddSum_eq_sq (n : Nat) : oddSum n = n * n := by
  -- Induction: prove it for 0, then show that if it holds for k, it holds for k + 1.
  induction n with
  | zero =>
    -- Step 1. No numbers add up to 0, and 0 * 0 = 0.
    rfl
  | succ k ih =>
    -- ih (the induction hypothesis) is the fact `oddSum k = k * k`.
    calc oddSum (k + 1)
        -- Step 2. Take the sum of k odd numbers and add the next one, 2k + 1.
        = oddSum k + (2 * k + 1)    := by rfl
        -- Step 3. The induction hypothesis says the first part is k * k.
      _ = k * k + (2 * k + 1)       := by rw [ih]
        -- Step 4. Two k's are k + k.
      _ = k * k + (k + k + 1)       := by rw [Nat.two_mul]
        -- Step 5. Group (k + k) + 1 as k + (k + 1).
      _ = k * k + (k + (k + 1))     := by rw [Nat.add_assoc k k 1]
        -- Step 6. Move the brackets: k*k + (k + rest) = (k*k + k) + rest.
      _ = k * k + k + (k + 1)       := by rw [Nat.add_assoc (k * k) k (k + 1)]
        -- Step 7. k*k + k is k copies of k, plus one more k: (k + 1) * k.
      _ = (k + 1) * k + (k + 1)     := by rw [Nat.add_one_mul]
        -- Step 8. (k + 1) copies of k, plus one more (k + 1): (k + 1) * (k + 1).
      _ = (k + 1) * (k + 1)         := by rw [Nat.mul_add_one]

/-- The same fact, checked by computation for one case: 1 + 3 + … + 19 = 100. -/
example : oddSum 10 = 100 := by decide

end LeanExample
