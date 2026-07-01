# F# Example

A short tour of F# on .NET 9 — pipelines, active patterns, discriminated unions, lazy sequences, and records.

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
