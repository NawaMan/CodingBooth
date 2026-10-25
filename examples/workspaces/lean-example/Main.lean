import LeanExample

open LeanExample

/-- Prints values the theorems in `LeanExample` vouch for. -/
def main (args : List String) : IO Unit := do
  let n := (args.head? >>= String.toNat?).getD 100
  IO.println s!"sumTo {n} = {sumTo n} = {n} * {n + 1} / 2"
  IO.println s!"fastFib {n} = {fastFib n}"
  IO.println s!"oddSum {n} = {oddSum n} = {n} * {n}"
