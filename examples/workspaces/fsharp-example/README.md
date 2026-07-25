# F# Example

This example is a niche F# on .NET 9 workspace that runs entirely inside the container. The bundled `Program.fs` reads `customers.csv`, prints summary statistics for age, income, and spending, then segments the customers with a small hand-rolled, seeded K-means clustering. The appeal here is that a niche toolchain never leaks onto your machine: the entire F#/.NET stack — SDK, runtime, and F# language server — lives inside the container. To try F#, you would normally install a multi-hundred-megabyte .NET SDK, register global tools, and leave that footprint behind on your host long after the experiment is over. Here you just launch the booth, run the analytics demo, and when you close it your host is exactly as clean as before — nothing installed, nothing to uninstall. It makes exploring an unfamiliar language a zero-commitment decision.

**Stack:** .NET SDK 9.0, F#

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/fsharp-example
booth

# 2. Inside the booth — build and run
./run-fsharp.sh
```

## What's included

| Component        | Details                                  |
|------------------|------------------------------------------|
| Runtime / SDK    | .NET 9.0                                 |
| VS Code support  | C# Dev Kit (provides F# language server) |
| Sample           | `Program.fs` — a short tour of F# idioms |

Override the .NET channel via the `DOTNET_CHANNEL` build arg in `.booth/Boothfile`.
