/-!
# A fast Fibonacci, proved equal to the slow one

`fib` is the textbook definition: obviously right, exponentially slow.
`fastFib` walks a pair of accumulators and is linear. The theorem says they agree
on every input, so `Main` can run the fast one and trust the answer.
-/

namespace LeanExample

/-- The specification: the definition straight from the textbook. -/
def fib : Nat → Nat
  | 0     => 0
  | 1     => 1
  | n + 2 => fib n + fib (n + 1)

/-- `n` more steps from the pair `(a, b)`. -/
def fibLoop : Nat → Nat → Nat → Nat
  | 0,     a, _ => a
  | n + 1, a, b => fibLoop n b (a + b)

/-- The implementation: linear time. -/
def fastFib (n : Nat) : Nat := fibLoop n 0 1

/-- Starting the loop at `(fib k, fib (k+1))` lands on `fib (n + k)`. -/
theorem fibLoop_spec (n k : Nat) : fibLoop n (fib k) (fib (k + 1)) = fib (n + k) := by
  induction n generalizing k with
  | zero => simp [fibLoop]
  | succ n ih =>
    have h : fib k + fib (k + 1) = fib (k + 2) := by simp [fib]
    simp only [fibLoop, h]
    rw [ih (k + 1)]
    congr 1
    omega

/-- The fast version computes exactly the specification. -/
theorem fastFib_eq_fib (n : Nat) : fastFib n = fib n := by
  have := fibLoop_spec n 0
  simpa [fastFib, fib] using this

end LeanExample
