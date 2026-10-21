(* Plain assertions, so the tests need nothing beyond the compiler and Dune. *)
let failures = ref 0

let check name actual expected =
  if actual <> expected then begin
    incr failures;
    Printf.printf "FAIL %s\n" name
  end

let value s = Result.bind (Calc.parse s) Calc.eval

let () =
  check "precedence" (value "1 + 2 * 3") (Ok 7);
  check "parentheses" (value "(1 + 2) * 3") (Ok 9);
  check "left-assoc sub" (value "10 - 4 - 3") (Ok 3);
  check "left-assoc div" (value "100 / 10 / 5") (Ok 2);
  check "unary minus" (value "-(2 + 3) * -2") (Ok 10);
  check "division by zero" (value "1 / (2 - 2)") (Error "division by zero");
  check "bad char" (value "2 ^ 3") (Error "unexpected '^' at column 3");
  check "missing paren" (value "(1 + 2") (Error "missing ')'");
  check "trailing input" (value "1 2")
    (Error "unexpected input after the expression");
  check "empty" (value "") (Error "unexpected end of input");
  check "printed" (Calc.calculate "1 + 2 * 3") (Ok "(1 + (2 * 3)) = 7");
  if !failures > 0 then exit 1;
  print_endline "All calc tests passed."
