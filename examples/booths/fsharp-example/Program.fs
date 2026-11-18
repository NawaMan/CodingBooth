// Customer analytics in F# — no external libraries.
// Reads customers.csv, reports summary statistics, then segments the customers
// into groups with a small hand-rolled K-means implementation.

open System
open System.IO

// ---------------------------------------------------------------------------
// 1. Load the CSV
// ---------------------------------------------------------------------------

type Customer = { Id: int; Age: int; Income: float; Spending: float }

let load path =
    File.ReadAllLines path
    |> Array.skip 1                                   // drop the header row
    |> Array.filter (fun line -> line.Trim() <> "")
    |> Array.map (fun line ->
        match line.Split(',') with
        | [| id; age; income; spending |] ->
            { Id = int id; Age = int age; Income = float income; Spending = float spending }
        | _ -> failwithf "malformed row: %s" line)
    |> Array.toList

// customers.csv is copied next to the built app, so resolve it from there.
let dataPath = Path.Combine(AppContext.BaseDirectory, "customers.csv")
let customers = load dataPath

printfn "=== Customer analytics (F# in CodingBooth) ==="
printfn "Loaded %d customers from %s\n" customers.Length (Path.GetFileName dataPath)

// ---------------------------------------------------------------------------
// 2. Summary statistics per column
// ---------------------------------------------------------------------------

let stats (values: float list) =
    let n = float values.Length
    let mean = List.sum values / n
    let variance = (values |> List.sumBy (fun v -> (v - mean) ** 2.0)) / n
    {| Mean = mean; Min = List.min values; Max = List.max values; Std = sqrt variance |}

let describe name (selector: Customer -> float) =
    let s = stats (customers |> List.map selector)
    printfn "  %-17s mean=%6.1f  min=%6.1f  max=%6.1f  std=%5.1f"
        name s.Mean s.Min s.Max s.Std

printfn "Summary statistics:"
describe "age"              (fun c -> float c.Age)
describe "income (k$)"      (fun c -> c.Income)
describe "spending (1-100)" (fun c -> c.Spending)
printfn ""

// ---------------------------------------------------------------------------
// 3. K-means clustering on (income, spending)
// ---------------------------------------------------------------------------

type Point = { Income: float; Spending: float }
let toPoint (c: Customer) = { Income = c.Income; Spending = c.Spending }

let dist a b =
    sqrt ((a.Income - b.Income) ** 2.0 + (a.Spending - b.Spending) ** 2.0)

let centroid points =
    let n = float (List.length points)
    { Income   = (points |> List.sumBy (fun p -> p.Income))   / n
      Spending = (points |> List.sumBy (fun p -> p.Spending)) / n }

// Index of the nearest centroid to point p.
let nearest centroids p =
    centroids |> List.mapi (fun i c -> i, dist p c) |> List.minBy snd |> fst

// Lloyd's algorithm: assign -> recompute -> repeat until stable (or maxIter).
// Seeded RNG keeps the initial centroids — and therefore the output — reproducible.
let kmeans k maxIter points =
    let rng = Random(42)
    let init = points |> List.sortBy (fun _ -> rng.Next()) |> List.distinct |> List.truncate k
    let rec loop centroids iter =
        let next =
            [ for i in 0 .. k - 1 ->
                let members = points |> List.filter (fun p -> nearest centroids p = i)
                if List.isEmpty members then centroids.[i] else centroid members ]
        if iter >= maxIter || next = centroids then next
        else loop next (iter + 1)
    loop init 0

let k = 3
let centroids = kmeans k 100 (customers |> List.map toPoint)

// Assign every customer to a segment, ordered by income for a readable report.
let segments =
    customers
    |> List.groupBy (fun c -> nearest centroids (toPoint c))
    |> List.sortBy (fun (ci, _) -> centroids.[ci].Income)

printfn "K-means clustering (k=%d) on income vs spending:" k
segments
|> List.iteri (fun idx (ci, members) ->
    let c = centroids.[ci]
    let ids = members |> List.map (fun m -> m.Id) |> List.sort
    printfn "  Segment %d: %2d customers | centroid income=%5.1fk spending=%4.1f"
        (idx + 1) (List.length members) c.Income c.Spending
    printfn "             customers: %s" (ids |> List.map string |> String.concat ", "))
