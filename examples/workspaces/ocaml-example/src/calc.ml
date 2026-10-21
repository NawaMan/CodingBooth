type op = Add | Sub | Mul | Div
type expr = Num of int | Neg of expr | Bin of op * expr * expr
type token = Int of int | Op of op | Lparen | Rparen

let ( let* ) = Result.bind

let tokenize s =
  let n = String.length s in
  let rec digits i =
    if i < n && '0' <= s.[i] && s.[i] <= '9' then digits (i + 1) else i
  in
  let rec go i acc =
    if i >= n then Ok (List.rev acc)
    else
      match s.[i] with
      | ' ' | '\t' -> go (i + 1) acc
      | '+' -> go (i + 1) (Op Add :: acc)
      | '-' -> go (i + 1) (Op Sub :: acc)
      | '*' -> go (i + 1) (Op Mul :: acc)
      | '/' -> go (i + 1) (Op Div :: acc)
      | '(' -> go (i + 1) (Lparen :: acc)
      | ')' -> go (i + 1) (Rparen :: acc)
      | '0' .. '9' -> (
          let j = digits i in
          match int_of_string_opt (String.sub s i (j - i)) with
          | Some v -> go j (Int v :: acc)
          | None ->
              Error (Printf.sprintf "number too large at column %d" (i + 1)))
      | c -> Error (Printf.sprintf "unexpected '%c' at column %d" c (i + 1))
  in
  go 0 []

(* Recursive descent: expr := term (('+'|'-') term)*,
   term := factor (('*'|'/') factor)*, factor := int | '-' factor | '(' expr ')'.
   Each function returns the parsed tree and the tokens it did not consume. *)
let rec expr tokens =
  let* lhs, rest = term tokens in
  binary_loop term [ Add; Sub ] lhs rest

and term tokens =
  let* lhs, rest = factor tokens in
  binary_loop factor [ Mul; Div ] lhs rest

and binary_loop operand ops lhs = function
  | Op op :: rest when List.mem op ops ->
      let* rhs, rest = operand rest in
      binary_loop operand ops (Bin (op, lhs, rhs)) rest
  | rest -> Ok (lhs, rest)

and factor = function
  | Int v :: rest -> Ok (Num v, rest)
  | Op Sub :: rest ->
      let* e, rest = factor rest in
      Ok (Neg e, rest)
  | Lparen :: rest -> (
      let* e, rest = expr rest in
      match rest with
      | Rparen :: rest -> Ok (e, rest)
      | _ -> Error "missing ')'")
  | [] -> Error "unexpected end of input"
  | _ -> Error "expected a number, '-' or '('"

let parse s =
  let* tokens = tokenize s in
  let* e, rest = expr tokens in
  match rest with
  | [] -> Ok e
  | _ -> Error "unexpected input after the expression"

let rec eval = function
  | Num v -> Ok v
  | Neg e -> Result.map ( ~- ) (eval e)
  | Bin (op, a, b) -> (
      let* x = eval a in
      let* y = eval b in
      match op with
      | Add -> Ok (x + y)
      | Sub -> Ok (x - y)
      | Mul -> Ok (x * y)
      | Div -> if y = 0 then Error "division by zero" else Ok (x / y))

let symbol = function Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"

let rec to_string = function
  | Num v -> string_of_int v
  | Neg e -> "-" ^ to_string e
  | Bin (op, a, b) ->
      Printf.sprintf "(%s %s %s)" (to_string a) (symbol op) (to_string b)

let calculate s =
  let* e = parse s in
  let* v = eval e in
  Ok (Printf.sprintf "%s = %d" (to_string e) v)
