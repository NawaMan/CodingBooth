/-!
# Exercises: lists

Proofs about a function written here, not about library ones, so a search for an
existing lemma cannot finish them.
-/

namespace Exercises

/-- Reverse a list, the slow way. -/
def rev {α : Type} : List α → List α
  | []      => []
  | x :: xs => rev xs ++ [x]

/-- Reversing keeps the length. -/
theorem rev_length {α : Type} (xs : List α) : (rev xs).length = xs.length := by
  sorry

/-- Reversing twice gives the list back. -/
theorem rev_rev {α : Type} (xs : List α) : rev (rev xs) = xs := by
  sorry

end Exercises
