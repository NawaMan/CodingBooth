(** A tiny integer calculator: [+ - * /], unary minus and parentheses. *)

type op = Add | Sub | Mul | Div
type expr = Num of int | Neg of expr | Bin of op * expr * expr

val parse : string -> (expr, string) result
(** Parse an expression; [*] and [/] bind tighter than [+] and [-], and all four
    are left-associative. *)

val eval : expr -> (int, string) result
(** Evaluate an expression; division by zero is an [Error]. *)

val to_string : expr -> string
(** Print an expression fully parenthesized, so the parse is visible. *)

val calculate : string -> (string, string) result
(** [parse], then [eval], rendered as ["<parenthesized> = <value>"]. *)
