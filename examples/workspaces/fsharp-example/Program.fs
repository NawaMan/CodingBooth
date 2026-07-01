// A short tour of F# — pipelines, active patterns, discriminated unions, and lazy sequences.

printfn "=== A tour of F# in CodingBooth ===\n"

// 1. Pipelines & higher-order functions
let squaresOfEvens =
    [1..20]
    |> List.filter (fun n -> n % 2 = 0)
    |> List.map (fun n -> n * n)
printfn "Squares of evens (1..20): %A" squaresOfEvens

// 2. Active patterns + pattern matching: FizzBuzz with no if/else
let (|DivisibleBy|_|) divisor n =
    if n % divisor = 0 then Some () else None

let fizzbuzz n =
    match n with
    | DivisibleBy 15 -> "FizzBuzz"
    | DivisibleBy 3  -> "Fizz"
    | DivisibleBy 5  -> "Buzz"
    | _              -> string n

printfn "FizzBuzz (1..15): %s" (String.concat " " [ for n in 1..15 -> fizzbuzz n ])

// 3. Discriminated union + recursion: a tiny expression evaluator
type Expr =
    | Num of float
    | Add of Expr * Expr
    | Sub of Expr * Expr
    | Mul of Expr * Expr

let rec eval =
    function
    | Num n      -> n
    | Add (a, b) -> eval a + eval b
    | Sub (a, b) -> eval a - eval b
    | Mul (a, b) -> eval a * eval b

// (2 + 3) * (10 - 4)
let expr = Mul (Add (Num 2.0, Num 3.0), Sub (Num 10.0, Num 4.0))
printfn "(2 + 3) * (10 - 4) = %g" (eval expr)

// 4. Lazy, infinite sequences: the first 10 Fibonacci numbers (arbitrary precision)
let fibs = Seq.unfold (fun (a, b) -> Some (a, (b, a + b))) (0I, 1I)
printfn "First 10 Fibonacci: %A" (fibs |> Seq.take 10 |> Seq.toList)

// 5. Records + pipelines: sort people by age
type Person = { Name: string; Age: int }

let people =
    [ { Name = "Grace"; Age = 45 }
      { Name = "Ada";   Age = 36 }
      { Name = "Alan";  Age = 41 } ]

printfn "\nPeople, oldest first:"
people
|> List.sortByDescending (fun p -> p.Age)
|> List.iter (fun p -> printfn "  %-6s %d" p.Name p.Age)
