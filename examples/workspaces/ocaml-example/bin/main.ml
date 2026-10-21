(* calc "1 + 2 * 3"  prints  (1 + (2 * 3)) = 7 *)
let () =
  match Array.to_list Sys.argv with
  | [] | [ _ ] | [ _; "" ] ->
      prerr_endline "usage: calc <expression>   e.g. calc \"(1 + 2) * 3\"";
      exit 2
  | _ :: args -> (
      match Calc.calculate (String.concat " " args) with
      | Ok line -> print_endline line
      | Error msg ->
          prerr_endline ("error: " ^ msg);
          exit 1)
