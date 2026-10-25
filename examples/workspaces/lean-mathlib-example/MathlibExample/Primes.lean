module

public import Mathlib

@[expose] public section

/-!
# There are infinitely many primes

Euclid's proof: for any `n`, the number `n! + 1` has a prime factor `p`. That `p` cannot be
`≤ n`, because then it would divide `n!` too, and so divide `1`. So there is a prime above
every `n`.

Every lemma used here (`Nat.minFac_prime`, `Nat.Prime.dvd_factorial`, …) comes from Mathlib.
Put the cursor on one and press F12 to see how it is proved there.
-/

namespace MathlibExample

open Nat

/-- For every `n` there is a prime `p ≥ n`. -/
theorem exists_prime_ge (n : ℕ) : ∃ p, n ≤ p ∧ p.Prime := by
  -- p is the smallest prime factor of n! + 1.
  let p := minFac (n ! + 1)
  -- n! + 1 ≠ 1, because n! > 0, so it has a prime factor.
  have hp : p.Prime := minFac_prime (by have := factorial_pos n; omega)
  refine ⟨p, ?_, hp⟩
  -- Suppose instead that p < n.
  by_contra! hlt
  -- Then p divides n! ...
  have h₁ : p ∣ n ! := hp.dvd_factorial.mpr hlt.le
  -- ... and p divides n! + 1, by definition ...
  have h₂ : p ∣ n ! + 1 := minFac_dvd _
  -- ... so p divides their difference, 1. No prime does.
  exact hp.not_dvd_one ((Nat.dvd_add_right h₁).mp h₂)

/-- The same fact, as Mathlib states it: the set of primes is infinite. -/
theorem primes_infinite : {p : ℕ | p.Prime}.Infinite :=
  Set.infinite_of_not_bddAbove fun ⟨n, hn⟩ =>
    let ⟨p, hnp, hp⟩ := exists_prime_ge (n + 1)
    absurd (hn hp) (by omega)

end MathlibExample
