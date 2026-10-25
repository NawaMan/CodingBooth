module

public import Mathlib

@[expose] public section

/-!
# Practice

A first proof of your own: `ring` proves any identity of commutative rings.
-/

namespace MathlibExample

example (a b : ℝ) : (a + b)^2 = a^2 + 2*a*b + b^2 := by
  ring

end MathlibExample
